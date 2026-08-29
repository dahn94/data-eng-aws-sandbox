output "instance_id" {
  description = "ID da instância"
  value       = module.ec2_instance.instance_id
}

output "public_ip" {
  description = "IP público — é o valor que vai em STREAMING_HOST da pipeline de streaming"
  value       = module.ec2_instance.public_ip
}

output "ssm_connect_command" {
  description = "Como abrir um shell na instância sem SSH"
  value       = module.ec2_instance.ssm_connect_command
}
