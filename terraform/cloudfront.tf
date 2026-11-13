resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name}-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Comportamiento 1: archivos estáticos -> TTL de 1 día.
resource "aws_cloudfront_cache_policy" "static_1d" {
  name        = "${local.name}-static-1d"
  comment     = "Frontend estático: TTL 1 día"
  min_ttl     = 0
  default_ttl = 86400
  max_ttl     = 86400

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

locals {
  api_origin_id      = "api-gateway"
  frontend_origin_id = "s3-frontend"
  # Política administrada de AWS: "SecurityHeadersPolicy" (HSTS, X-Frame-Options...)
  security_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03"
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  comment             = "${local.name} - telemedicina"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  http_version        = "http2and3"

  origin {
    origin_id                = local.frontend_origin_id
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    origin_id   = local.api_origin_id
    domain_name = "${aws_api_gateway_rest_api.main.id}.execute-api.${local.region}.amazonaws.com"
    origin_path = "/${aws_api_gateway_stage.prod.stage_name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ---- Comportamiento por defecto: estáticos (TTL 1 día) ----
  default_cache_behavior {
    target_origin_id           = local.frontend_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.static_1d.id
    response_headers_policy_id = local.security_headers_policy_id
  }

  # ---- Comportamiento /api/*: TTL 0 + Authorization en la whitelist ----
  # Se usa la configuración "legacy" (forwarded_values) porque una cache policy
  # con TTL 0 no permite incluir headers, y CloudFront no deja reenviar
  # Authorization mediante una origin request policy.
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = local.api_origin_id
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type", "Accept"]
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = var.allowed_countries
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
