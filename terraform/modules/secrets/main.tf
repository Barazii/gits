resource "aws_secretsmanager_secret" "github_token" {
  name = "${var.project_name}-github-token"

  tags = {
    Name = "${var.project_name}-github-token"
  }
}

resource "aws_secretsmanager_secret_version" "github_token" {
  secret_id = aws_secretsmanager_secret.github_token.id
  secret_string = jsonencode({
    oauthToken = var.github_token
  })
}
