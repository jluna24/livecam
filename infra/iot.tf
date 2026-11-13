# Identidad de la Pi (paso 3): IoT thing + certificado X.509 + role alias.
# La Pi cambia su certificado por credenciales temporales en el IoT credentials
# provider; no tiene access keys fijas.
#
# La llave privada se genera en la Pi y nunca sale de ahí: aquí solo se firma
# su CSR (infra/pi.csr, fuera de git). Ver pi/README.md.

resource "aws_iot_thing" "pi" {
  # Mismo nombre que el canal: la política del rol usa ${credentials-iot:ThingName}.
  name = local.channel_name
}

resource "aws_iot_certificate" "pi" {
  csr    = file(var.pi_csr_path)
  active = true
}

resource "aws_iot_thing_principal_attachment" "pi" {
  thing     = aws_iot_thing.pi.name
  principal = aws_iot_certificate.pi.arn
}

# --- Rol que asume el credentials provider en nombre de la Pi ---

data "aws_iam_policy_document" "pi_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["credentials.iot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pi_master" {
  name               = "${local.name}-pi-master"
  assume_role_policy = data.aws_iam_policy_document.pi_trust.json
}

data "aws_iam_policy_document" "pi_master" {
  statement {
    sid = "MasterDeSuCanal"
    actions = [
      "kinesisvideo:DescribeSignalingChannel",
      "kinesisvideo:ConnectAsMaster",
      "kinesisvideo:GetSignalingChannelEndpoint",
      "kinesisvideo:GetIceServerConfig",
    ]
    # Solo el canal con el mismo nombre que el thing que presenta el certificado.
    resources = [
      "arn:aws:kinesisvideo:${var.region}:${local.account_id}:channel/$${credentials-iot:ThingName}/*",
    ]
  }
}

resource "aws_iam_role_policy" "pi_master" {
  name   = "kvs-master"
  role   = aws_iam_role.pi_master.id
  policy = data.aws_iam_policy_document.pi_master.json
}

resource "aws_iot_role_alias" "pi" {
  alias               = "${local.name}-pi-master"
  role_arn            = aws_iam_role.pi_master.arn
  credential_duration = 3600
}

# --- Política de IoT: el certificado solo puede asumir ese role alias ---

data "aws_iam_policy_document" "pi_iot" {
  statement {
    actions   = ["iot:AssumeRoleWithCertificate"]
    resources = [aws_iot_role_alias.pi.arn]
  }
}

resource "aws_iot_policy" "pi" {
  name   = "${local.name}-pi"
  policy = data.aws_iam_policy_document.pi_iot.json
}

resource "aws_iot_policy_attachment" "pi" {
  policy = aws_iot_policy.pi.name
  target = aws_iot_certificate.pi.arn
}

data "aws_iot_endpoint" "credentials" {
  endpoint_type = "iot:CredentialProvider"
}
