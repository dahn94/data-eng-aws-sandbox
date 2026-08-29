output "instance_id" {
  description = "ID da instância"
  value       = module.ec2_instance.instance_id
}

output "public_ip" {
  description = "IP público — use como streaming_host quando o job Glue roda FORA da VPC, e para alcançar as UIs da sua máquina"
  value       = module.ec2_instance.public_ip
}

output "private_ip" {
  description = <<-EOT
    IP privado — é este o valor de `streaming_host` quando o
    workloads/webevents-streaming roda com `enable_vpc_connection = true`. O
    job entra pela VPC, então o endereço público não é usado e nada precisa
    estar exposto.
  EOT
  value       = module.ec2_instance.private_ip
}

output "ssm_connect_command" {
  description = "Como abrir um shell na instância sem SSH"
  value       = module.ec2_instance.ssm_connect_command
}
