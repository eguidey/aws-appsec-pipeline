output "aws_region" {
  description = "Region - add as the AWS_REGION GitHub variable."
  value       = local.region
}

output "github_deploy_role_arn" {
  description = "Add as the AWS_DEPLOY_ROLE_ARN GitHub variable."
  value       = aws_iam_role.github_deploy.arn
}

output "ecr_repository_name" {
  description = "Add as the ECR_REPOSITORY GitHub variable."
  value       = aws_ecr_repository.api.name
}

output "ecs_cluster_name" {
  description = "Add as the ECS_CLUSTER GitHub variable."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Add as the ECS_SERVICE GitHub variable."
  value       = aws_ecs_service.api.name
}

output "ecs_task_family" {
  description = "Add as the ECS_TASK_FAMILY GitHub variable."
  value       = aws_ecs_task_definition.api.family
}

output "app_log_group" {
  description = "CloudWatch log group with the application's JSON security telemetry."
  value       = aws_cloudwatch_log_group.api.name
}

output "demo_password_secret" {
  description = "Secrets Manager secret holding the /api/login demo password."
  value       = aws_secretsmanager_secret.demo_password.name
}

output "find_public_ip_command" {
  description = "Run this to get the running task's public IP address."
  value       = "aws ecs describe-tasks --cluster ${aws_ecs_cluster.main.name} --tasks $(aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.api.name} --query 'taskArns[0]' --output text) --query \"tasks[0].attachments[0].details[?name=='networkInterfaceId'].value\" --output text | xargs -I{} aws ec2 describe-network-interfaces --network-interface-ids {} --query 'NetworkInterfaces[0].Association.PublicIp' --output text"
}
