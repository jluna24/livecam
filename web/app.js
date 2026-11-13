// livecam — viewer WebRTC de KVS para el celular.
// 1) Login con Cognito (código de autorización + PKCE, sin secreto).
// 2) Identity Pool: id_token → credenciales temporales de viewer.
// 3) KVS: endpoint del canal + servidores ICE (firmados con aws4fetch).
// 4) WebRTC: oferta solo de recepción de video; el master (Pi) responde.
'use strict';

const C = window.LIVECAM;
const $ = (id) => document.getElementById(id);
const ui = {
  video: $('video'), overlay: $('overlay'), mensaje: $('mensaje'),
  entrar: $('btn-entrar'), conectar: $('btn-conectar'),
  reconectar: $('btn-reconectar'), salir: $('btn-salir'),
  estado: $('estado'), ruta: $('ruta'),
};
const RT_KEY = 'livecam.refresh';

let sesion = null;   // { pc, signaling }
let statsTimer = null;

// ---------- utilidades ----------

function estado(texto, clase = '') {
  ui.estado.textContent = texto;
  ui.estado.className = `estado ${clase}`;
}

function overlay(mensaje, { entrar = false, conectar = false } = {}) {
  ui.overlay.hidden = false;
  ui.mensaje.textContent = mensaje;
  ui.entrar.hidden = !entrar;
  ui.conectar.hidden = !conectar;
}

function b64url(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function aleatorio(n = 32) {
  return b64url(crypto.getRandomValues(new Uint8Array(n)));
}

function guardar(k, v) { try { localStorage.setItem(k, v); } catch { /* modo privado */ } }
function leer(k) { try { return localStorage.getItem(k); } catch { return null; } }
function borrar(k) { try { localStorage.removeItem(k); } catch { /* nada */ } }

// ---------- 1) Cognito: login con PKCE ----------

async function iniciarLogin() {
  const verifier = aleatorio(48);
  const state = aleatorio(16);
  sessionStorage.setItem('livecam.pkce', verifier);
  sessionStorage.setItem('livecam.state', state);
  const challenge = b64url(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier)));
  const q = new URLSearchParams({
    response_type: 'code',
    client_id: C.clientId,
    redirect_uri: C.redirectUri,
    scope: 'openid email',
    state,
    code_challenge_method: 'S256',
    code_challenge: challenge,
  });
  location.assign(`${C.authDomain}/oauth2/authorize?${q}`);
}

async function pedirToken(params) {
  const r = await fetch(`${C.authDomain}/oauth2/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: C.clientId, ...params }),
  });
  if (!r.ok) throw new Error(`token ${r.status}`);
  return r.json();
}

// Devuelve un id_token válido, o null si hay que iniciar sesión.
async function obtenerIdToken() {
  const url = new URL(location.href);
  const code = url.searchParams.get('code');
  if (code) {
    const state = url.searchParams.get('state');
    const verifier = sessionStorage.getItem('livecam.pkce');
    history.replaceState(null, '', C.redirectUri);   // quitar ?code= de la barra
    if (!verifier || state !== sessionStorage.getItem('livecam.state')) return null;
    sessionStorage.removeItem('livecam.pkce');
    sessionStorage.removeItem('livecam.state');
    const t = await pedirToken({
      grant_type: 'authorization_code', code, redirect_uri: C.redirectUri, code_verifier: verifier,
    });
    if (t.refresh_token) guardar(RT_KEY, t.refresh_token);
    return t.id_token;
  }
  const rt = leer(RT_KEY);
  if (!rt) return null;
  try {
    const t = await pedirToken({ grant_type: 'refresh_token', refresh_token: rt });
    return t.id_token;
  } catch {
    borrar(RT_KEY);   // vencido o revocado
    return null;
  }
}

function salir() {
  borrar(RT_KEY);
  cerrarSesion();
  const q = new URLSearchParams({ client_id: C.clientId, logout_uri: C.redirectUri });
  location.assign(`${C.authDomain}/logout?${q}`);
}

// ---------- 2) Identity Pool: credenciales temporales ----------

async function cognitoIdentity(target, body) {
  const r = await fetch(`https://cognito-identity.${C.region}.amazonaws.com/`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-amz-json-1.1',
      'X-Amz-Target': `AWSCognitoIdentityService.${target}`,
    },
    body: JSON.stringify(body),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`${target}: ${j.message || j.__type || r.status}`);
  return j;
}

async function credenciales(idToken) {
  const Logins = { [C.userPoolLogin]: idToken };
  const { IdentityId } = await cognitoIdentity('GetId', { IdentityPoolId: C.identityPoolId, Logins });
  const { Credentials: c } = await cognitoIdentity('GetCredentialsForIdentity', { IdentityId, Logins });
  return { accessKeyId: c.AccessKeyId, secretAccessKey: c.SecretKey, sessionToken: c.SessionToken };
}

// ---------- 3) y 4) KVS + WebRTC ----------

async function kvs(aws, url, body) {
  const r = await aws.fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`KVS ${r.status}: ${j.message || j.Message || ''}`);
  return j;
}

function cerrarSesion() {
  clearInterval(statsTimer);
  if (sesion) {
    try { sesion.signaling.close(); } catch { /* nada */ }
    try { sesion.pc.close(); } catch { /* nada */ }
  }
  sesion = null;
  ui.video.srcObject = null;
  ui.ruta.textContent = '';
}

async function conectar() {
  cerrarSesion();
  ui.conectar.hidden = true;
  ui.reconectar.hidden = true;
  overlay('Conectando…');
  estado('Conectando', 'warn');

  const idToken = await obtenerIdToken();
  if (!idToken) {
    overlay('Inicia sesión para ver la cámara.', { entrar: true });
    estado('Sin sesión');
    ui.salir.hidden = true;
    return;
  }
  ui.salir.hidden = false;

  const creds = await credenciales(idToken);
  const aws = new aws4fetch.AwsClient({ ...creds, service: 'kinesisvideo', region: C.region });
  const clientId = `viewer-${aleatorio(9)}`;
  const role = KVSWebRTC.Role.VIEWER;

  const ep = await kvs(aws, `https://kinesisvideo.${C.region}.amazonaws.com/getSignalingChannelEndpoint`, {
    ChannelARN: C.channelArn,
    SingleMasterChannelEndpointConfiguration: { Protocols: ['WSS', 'HTTPS'], Role: role },
  });
  const endpoints = Object.fromEntries(ep.ResourceEndpointList.map((e) => [e.Protocol, e.ResourceEndpoint]));

  const ice = await kvs(aws, `${endpoints.HTTPS}/v1/get-ice-server-config`, {
    ChannelARN: C.channelArn, ClientId: clientId,
  });
  const iceServers = [{ urls: `stun:stun.kinesisvideo.${C.region}.amazonaws.com:443` }];
  for (const s of ice.IceServerList || []) {
    iceServers.push({ urls: s.Uris, username: s.Username, credential: s.Password });
  }

  const pc = new RTCPeerConnection({ iceServers });
  pc.addTransceiver('video', { direction: 'recvonly' });

  const signaling = new KVSWebRTC.SignalingClient({
    channelARN: C.channelArn,
    channelEndpoint: endpoints.WSS,
    clientId,
    role,
    region: C.region,
    credentials: creds,
    systemClockOffset: 0,
  });
  sesion = { pc, signaling };

  signaling.on('open', async () => {
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    signaling.sendSdpOffer(pc.localDescription);
    overlay('Esperando a la cámara…');
  });
  signaling.on('sdpAnswer', (answer) => pc.setRemoteDescription(answer));
  signaling.on('iceCandidate', (c) => pc.addIceCandidate(c).catch(() => {}));
  signaling.on('error', (e) => console.warn('señalización', e));

  pc.addEventListener('icecandidate', ({ candidate }) => {
    if (candidate) signaling.sendIceCandidate(candidate);
  });
  pc.addEventListener('track', (ev) => {
    ui.video.srcObject = ev.streams[0] || new MediaStream([ev.track]);
    ui.video.play().catch(() => {});
  });
  pc.addEventListener('connectionstatechange', () => {
    const s = pc.connectionState;
    if (s === 'connected') {
      ui.overlay.hidden = true;
      estado('En vivo', 'ok');
      ui.reconectar.hidden = false;
      mostrarRuta(pc);
      statsTimer = setInterval(() => mostrarRuta(pc), 5000);
    } else if (s === 'failed' || s === 'disconnected' || s === 'closed') {
      estado(s === 'failed' ? 'Falló la conexión' : 'Desconectado', 'err');
      overlay('Se perdió la conexión con la cámara.', { conectar: true });
    }
  });

  signaling.open();
}

// Muestra si el video llega directo (P2P) o por TURN, y la resolución/fps.
async function mostrarRuta(pc) {
  try {
    const stats = await pc.getStats();
    let par = null; let inbound = null;
    stats.forEach((r) => {
      if (r.type === 'transport' && r.selectedCandidatePairId) par = stats.get(r.selectedCandidatePairId);
      if (r.type === 'inbound-rtp' && r.kind === 'video') inbound = r;
    });
    if (!par) stats.forEach((r) => { if (r.type === 'candidate-pair' && r.nominated && r.state === 'succeeded') par = r; });
    const local = par && stats.get(par.localCandidateId);
    const remota = par && stats.get(par.remoteCandidateId);
    const turn = local?.candidateType === 'relay' || remota?.candidateType === 'relay';
    const partes = [turn ? 'vía TURN' : 'directo (P2P)'];
    if (inbound?.frameWidth) partes.push(`${inbound.frameWidth}×${inbound.frameHeight}`);
    if (inbound?.framesPerSecond) partes.push(`${Math.round(inbound.framesPerSecond)} fps`);
    ui.ruta.textContent = partes.join(' · ');
  } catch { /* stats no disponibles */ }
}

// ---------- arranque ----------

function fallo(e) {
  console.error(e);
  estado('Error', 'err');
  overlay(`No se pudo conectar: ${e.message || e}`, { conectar: true });
}

ui.entrar.addEventListener('click', () => iniciarLogin().catch(fallo));
ui.conectar.addEventListener('click', () => conectar().catch(fallo));
ui.reconectar.addEventListener('click', () => conectar().catch(fallo));
ui.salir.addEventListener('click', salir);

// Al volver a la pestaña (p. ej. tras bloquear el celular), reconectar si se cayó.
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && sesion &&
      ['failed', 'disconnected', 'closed'].includes(sesion.pc.connectionState)) {
    conectar().catch(fallo);
  }
});

if (!C) {
  overlay('Falta config.js.');
} else {
  conectar().catch(fallo);
}
