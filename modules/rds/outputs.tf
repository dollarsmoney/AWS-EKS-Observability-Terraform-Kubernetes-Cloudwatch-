output "instance_id" {
  value = aws_db_instance.this.identifier # the "DBInstanceIdentifier" dimension in CloudWatch
}

output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "username" {
  value = aws_db_instance.this.username
}

output "master_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "postgres_log_group_name" {
  value = aws_cloudwatch_log_group.rds["postgresql"].name
}
