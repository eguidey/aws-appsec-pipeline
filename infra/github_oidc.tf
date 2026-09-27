# GitHub Actions authenticates to AWS with short-lived OIDC tokens.
# No long-lived access keys are ever stored in GitHub.

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS validates GitHub's certificate itself; these values are kept for older provider versions.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

data "aws_iam_openid_connect_provider" "github_existing" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github_existing[0].arn

  # Repositories created after 2026-07-15 send an "immutable" subject that includes numeric IDs:
  #   repo:OWNER@OWNER_ID/REPO@REPO_ID:...   (older repos send repo:OWNER/REPO:...)
  # The IDs stop a deleted-and-recreated repo with the same name from inheriting this role.
  github_repo_owner = split("/", var.github_repository)[0]
  github_repo_name  = split("/", var.github_repository)[1]
  github_subject_repos = compact([
    "repo:${var.github_repository}",
    var.github_owner_id != "" && var.github_repository_id != "" ? "repo:${local.github_repo_owner}@${var.github_owner_id}/${local.github_repo_name}@${var.github_repository_id}" : "",
  ])
  github_allowed_subjects = flatten([
    for repo in local.github_subject_repos : [
      "${repo}:ref:refs/heads/${var.github_deploy_branch}",
      "${repo}:environment:${var.github_environment}",
    ]
  ])
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only this repository can assume the role, and only from the deploy branch or the
    # protected deployment environment - never from forks, pull requests or other branches.
    # (Jobs that use a GitHub environment present a different "sub" claim, so both are listed.)
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_allowed_subjects
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name                 = "${local.name}-github-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # no resource-level support for this action
  }
  statement {
    sid = "PushToThisRepositoryOnly"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
    ]
    resources = [aws_ecr_repository.api.arn]
  }
  statement {
    sid       = "TaskDefinitions"
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
    resources = ["*"] # these actions do not support resource-level permissions
  }
  statement {
    sid       = "DeployThisServiceOnly"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [aws_ecs_service.api.id]
  }
  statement {
    sid       = "SmokeTestDescribeTasksInThisClusterOnly"
    actions   = ["ecs:DescribeTasks"]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:task/${aws_ecs_cluster.main.name}/*"]
  }
  statement {
    sid       = "SmokeTestListTasksInThisClusterOnly"
    actions   = ["ecs:ListTasks"]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:container-instance/${aws_ecs_cluster.main.name}/*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.main.arn]
    }
  }
  statement {
    sid       = "SmokeTestFindTaskPublicIp"
    actions   = ["ec2:DescribeNetworkInterfaces"]
    resources = ["*"] # read-only; EC2 Describe* actions have no resource-level support
  }
  statement {
    sid       = "PassOnlyTheExecutionRoleToEcs"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "least-privilege-deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
