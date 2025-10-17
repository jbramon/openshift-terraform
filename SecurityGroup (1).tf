resource "aws_security_group" "pair14-sg" {
  name        = "pair14-sg"
  description = "pair14-sg"
  tags = {
    Name = "pair14-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "sshfromyIP" {
  security_group_id = aws_security_group.pair14-sg.id
  cidr_ipv4         = "155.137.106.21/32"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_http" {
  security_group_id = aws_security_group.pair14-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_https" {
  security_group_id = aws_security_group.pair14-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "allowOutbound_http" {
  security_group_id = aws_security_group.pair14-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "allowOutbound_https" {
  security_group_id = aws_security_group.pair14-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "allow_openshift_api" {
  security_group_id = aws_security_group.pair14-sg.id
  cidr_ipv4         = "52.204.60.140/32"
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
}



