output "instance_id" {
  description = "ID da instância criada"
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "IP público da instância"
  value       = aws_instance.this.public_ip
}

output "private_ip" {
  description = "IP privado da instância"
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "ID do Security Group criado"
  value       = aws_security_group.this.id
}

output "ssm_connect_command" {
  description = "Comando para abrir um shell na instância sem SSH"
  value       = "aws ssm start-session --target ${aws_instance.this.id}"
}
