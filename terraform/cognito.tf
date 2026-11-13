# ---------------------------------------------------------------------------
# Dos User Pools separados con atributos personalizados distintos.
# Los atributos custom:* se incluyen automáticamente como claims en el ID token.
# custom:role y custom:license NO son escribibles por el app client: solo un
# administrador puede asignarlos (admin-create-user), así el usuario no puede
# auto-promoverse a médico.
# ---------------------------------------------------------------------------

locals {
  password_policy = {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }
}

# =============================== MÉDICOS ===================================

resource "aws_cognito_user_pool" "medicos" {
  name                     = "${local.name}-medicos"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length    = local.password_policy.minimum_length
    require_lowercase = local.password_policy.require_lowercase
    require_uppercase = local.password_policy.require_uppercase
    require_numbers   = local.password_policy.require_numbers
    require_symbols   = local.password_policy.require_symbols
  }

  schema {
    name                = "role"
    attribute_data_type = "String"
    mutable             = true
    string_attribute_constraints {
      min_length = 1
      max_length = 20
    }
  }

  schema {
    name                = "license"
    attribute_data_type = "String"
    mutable             = true
    string_attribute_constraints {
      min_length = 4
      max_length = 30
    }
  }

  schema {
    name                = "specialty"
    attribute_data_type = "String"
    mutable             = true
    string_attribute_constraints {
      min_length = 1
      max_length = 60
    }
  }
}

resource "aws_cognito_user_pool_client" "medicos" {
  name         = "${local.name}-medicos-web"
  user_pool_id = aws_cognito_user_pool.medicos.id

  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"
  explicit_auth_flows           = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  id_token_validity      = 60
  access_token_validity  = 60
  refresh_token_validity = 1
  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }

  read_attributes  = ["email", "name", "custom:role", "custom:license", "custom:specialty"]
  write_attributes = ["name"] # role/license/specialty solo los cambia un admin
}

# ============================== PACIENTES ==================================

resource "aws_cognito_user_pool" "pacientes" {
  name                     = "${local.name}-pacientes"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length    = local.password_policy.minimum_length
    require_lowercase = local.password_policy.require_lowercase
    require_uppercase = local.password_policy.require_uppercase
    require_numbers   = local.password_policy.require_numbers
    require_symbols   = local.password_policy.require_symbols
  }

  schema {
    name                = "role"
    attribute_data_type = "String"
    mutable             = true
    string_attribute_constraints {
      min_length = 1
      max_length = 20
    }
  }

  schema {
    name                = "document_id"
    attribute_data_type = "String"
    mutable             = true
    string_attribute_constraints {
      min_length = 5
      max_length = 20
    }
  }

  schema {
    name                = "eps"
    attribute_data_type = "String"
    mutable             = true
    string_attribute_constraints {
      min_length = 1
      max_length = 60
    }
  }
}

resource "aws_cognito_user_pool_client" "pacientes" {
  name         = "${local.name}-pacientes-web"
  user_pool_id = aws_cognito_user_pool.pacientes.id

  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"
  explicit_auth_flows           = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  id_token_validity      = 60
  access_token_validity  = 60
  refresh_token_validity = 1
  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }

  read_attributes  = ["email", "name", "custom:role", "custom:document_id", "custom:eps"]
  write_attributes = ["name", "custom:eps"]
}
