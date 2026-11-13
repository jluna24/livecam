# Login del celular (paso 4): Cognito User Pool (sin registro abierto) +
# Identity Pool que cambia el token por credenciales temporales de *viewer*.

resource "aws_cognito_user_pool" "main" {
  name           = local.name
  user_pool_tier = "LITE"

  # Se entra con el correo. Los usuarios los crea el administrador (CLI); no hay registro.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 3
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  deletion_protection = "INACTIVE" # para que `tofu destroy` funcione
}

# Dominio del login de Cognito (hosted UI clásico). El prefijo no expone el ID de la cuenta.
resource "aws_cognito_user_pool_domain" "main" {
  domain                = "${local.name}-${substr(sha256(local.account_id), 0, 10)}"
  user_pool_id          = aws_cognito_user_pool.main.id
  managed_login_version = 1
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${local.name}-web"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = false # página estática: código de autorización + PKCE
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = [local.web_url]
  logout_urls                          = [local.web_url]

  explicit_auth_flows           = ["ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  id_token_validity      = 60
  access_token_validity  = 60
  refresh_token_validity = 30
  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }
}

resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = local.name
  allow_unauthenticated_identities = false
  allow_classic_flow               = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.web.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = true
  }
}

# --- Rol de viewer para usuarios autenticados ---

data "aws_iam_policy_document" "viewer_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "cognito-identity.amazonaws.com:aud"
      values   = [aws_cognito_identity_pool.main.id]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["authenticated"]
    }
  }
}

resource "aws_iam_role" "viewer" {
  name               = "${local.name}-viewer"
  assume_role_policy = data.aws_iam_policy_document.viewer_trust.json
}

data "aws_iam_policy_document" "viewer" {
  statement {
    sid = "ViewerDelCanal"
    actions = [
      "kinesisvideo:DescribeSignalingChannel",
      "kinesisvideo:ConnectAsViewer",
      "kinesisvideo:GetSignalingChannelEndpoint",
      "kinesisvideo:GetIceServerConfig",
    ]
    resources = [awscc_kinesisvideo_signaling_channel.cam.arn]
  }
}

resource "aws_iam_role_policy" "viewer" {
  name   = "kvs-viewer"
  role   = aws_iam_role.viewer.id
  policy = data.aws_iam_policy_document.viewer.json
}

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id
  roles = {
    authenticated = aws_iam_role.viewer.arn
  }
}
