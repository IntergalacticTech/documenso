# Builds the fork's container image on a native arm64 CodeBuild host and
# pushes it to a private ECR repository the app host can pull from. Started on
# demand by scripts/build-image.sh with the git ref to build.

resource "aws_ecr_repository" "app" {
  name                 = var.name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 20 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "build" {
  name              = "/${var.name}/build"
  retention_in_days = 30
}

resource "aws_iam_role" "build" {
  name = "${var.name}-build"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "build" {
  name = "build"
  role = aws_iam_role.build.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.build.arn}:*"
      },
    ]
  })
}

resource "aws_codebuild_project" "app" {
  name          = "${var.name}-image"
  service_role  = aws_iam_role.build.arn
  build_timeout = 60

  source {
    type      = "NO_SOURCE"
    buildspec = <<-EOT
      version: 0.2
      phases:
        pre_build:
          commands:
            - git clone --depth 1 --branch "$GIT_REF" "$REPO_URL" /tmp/src
            - echo "sha-$(git -C /tmp/src rev-parse --short=12 HEAD)" > /tmp/image-tag
            - aws ecr get-login-password | docker login --username AWS --password-stdin "$${ECR_REPO%%/*}"
        build:
          commands:
            - docker build -f /tmp/src/docker/Dockerfile -t "$ECR_REPO:$(cat /tmp/image-tag)" /tmp/src
        post_build:
          commands:
            - docker push "$ECR_REPO:$(cat /tmp/image-tag)"
            - echo "IMAGE=$ECR_REPO:$(cat /tmp/image-tag)"
    EOT
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    type            = "ARM_CONTAINER"
    compute_type    = "BUILD_GENERAL1_LARGE"
    image           = "aws/codebuild/amazonlinux-aarch64-standard:3.0"
    privileged_mode = true

    environment_variable {
      name  = "REPO_URL"
      value = var.source_repo_url
    }

    environment_variable {
      name  = "GIT_REF"
      value = "main"
    }

    environment_variable {
      name  = "ECR_REPO"
      value = aws_ecr_repository.app.repository_url
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }
}
