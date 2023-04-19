output "leader-manager-public-ip" {
  value = aws_instance.instance-leader-manager.public_ip
}

output "website-url" {
  value = "http://${aws_instance.instance-leader-manager.public_ip}"
}

output "viz-url" {
  value = "http://${aws_instance.instance-leader-manager.public_ip}:8080"
}

output "manager-public-ip" {
  value = aws_instance.instance-manager.*.public_ip
}

output "worker-public-ip" {
  value = aws_instance.instance-worker.*.public_ip
}

output "ecr-repo-url" {
  value = aws_ecr_repository.ecr-repo.repository_url
}