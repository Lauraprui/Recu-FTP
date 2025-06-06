resource "aws_security_group" "sg_ftp_servidor" {
  vpc_id = aws_vpc.red_primaria.id

  # Permitir acceso FTP (control)
  ingress {
    from_port   = 21
    to_port     = 21
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir canal de datos FTP
  ingress {
    from_port   = 20
    to_port     = 20
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir conexiones seguras TLS para FTP
  ingress {
    from_port = 990
    to_port = 990
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Rango de puertos pasivos para FTP
  ingress {
    from_port   = 2100
    to_port     = 2101
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir acceso SSH para administración
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir todo el tráfico saliente
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SG para Servidor FTP"
  }
}

resource "aws_security_group" "sg_bastionado" {
  name   = "sg_bastionado"
  vpc_id = aws_vpc.red_secundaria.id

  # Permitir SSH desde cualquier lugar
  ingress {
    description      = "Permitir SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SG para bastionado"
  }
}

resource "aws_security_group" "sg_ldap_servidor" {
  name   = "sg_ldap"
  vpc_id = aws_vpc.red_secundaria.id

  # Permitir SSH para administración
  ingress {
    description      = "Permitir SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  # Permitir LDAP
  ingress {
    description      = "Permitir LDAP"
    from_port        = 389
    to_port          = 389
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "SG para LDAP"
  }
}

# IP elástica para el servidor FTP
resource "aws_eip" "eip_ftp" {
  instance = aws_instance.instancia_ftp.id

  tags = {
    Name = "EIP FTP"
  }
}

output "ip_publica_ftp" {
  value = aws_eip.eip_ftp.public_ip
  description = "IP Pública del Servidor FTP"
}

output "ip_bastionado"{
  value = aws_instance.instancia_bastionado.public_ip
  description = "IP Pública del bastionado"
}

output "ip_ldap_privada"{
  value = aws_instance.instancia_ldap.private_ip
  description = "IP Privada del LDAP"
}

# Asociación de la IP elástica al servidor FTP
resource "aws_eip_association" "asociacion_eip_ftp" {
  instance_id   = aws_instance.instancia_ftp.id
  allocation_id = aws_eip.eip_ftp.id
}

# Instancia bastionado
resource "aws_instance" "instancia_bastionado" {
  ami                    = "ami-064519b8c76274859"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subred_publica_secundaria.id
  key_name               = "arwen"
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.sg_bastionado.id]

  user_data = <<-EOF
#!/bin/bash
apt update -y
  EOF

  tags = {
    Name = "bastionado"
  }
}

# Instancia FTP en la subred pública principal
resource "aws_instance" "instancia_ftp" {
  ami           = "ami-064519b8c76274859"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subred_publica_primaria.id
  key_name      = "arwen"
  depends_on    = [ aws_instance.instancia_ldap ]
  vpc_security_group_ids = [aws_security_group.sg_ftp_servidor.id]
  user_data = <<-EOF
#!/bin/bash
sleep 50

apt update -y
apt install vim -y
# Instalación de Docker y utilidades
apt install ca-certificates curl -y
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update -y
apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-compose -y
apt install jq -y

# Configuración AWS
apt install s3fs -y
mkdir /root/.aws

cat <<-CREDENTIALS > /root/.aws/credentials
[default]
aws_access_key_id=${var.aws_access_key_id}
aws_secret_access_key=${var.aws_secret_access_key}
aws_session_token=${var.aws_session_token}
CREDENTIALS

apt install cron -y
apt install rsync -y

mkdir -p /home/admin/ftp

mkdir /mnt/bucket-s3
chmod 777 /mnt/bucket-s3
systemctl enable cron

systemctl start cron
systemctl enable cron

(crontab -l 2>/dev/null; echo "* * * * * rsync -av /home/admin/ftp/ /mnt/bucket-s3/") | crontab -

s3fs bucket-laura-cubito /mnt/bucket-s3 -o allow_other

mkdir -p /home/docker
cd /home/docker

# Crear Dockerfile para el servidor FTP
cat <<-DOCKERFILE > dockerfile
FROM debian:latest

# Dependencias necesarias
RUN apt-get update && apt-get install -y proftpd openssl nano proftpd-mod-crypto proftpd-mod-ldap ldap-utils

# Módulos adicionales
RUN apt-get update && apt-get install -y proftpd-mod-crypto && apt-get install proftpd-mod-ldap -y

RUN useradd -m -s /bin/bash ${var.ftp_user} && echo "${var.ftp_user}:${var.ftp_password}" | chpasswd

RUN mkdir -p /home/admin/ftp && chown -R ${var.ftp_user}:${var.ftp_user} /home/admin && chmod -R 777 /home/admin && chmod -R 777 /home/

# Certificado para ProFTPD
RUN openssl req -x509 -newkey rsa:2048 -sha256 -keyout /etc/ssl/private/proftpd.key -out /etc/ssl/certs/proftpd.crt -nodes -days 365 \
    -subj "/C=ES/ST=España/L=Granada/O=ftporg/OU=ftporg/CN=ftp.lauraftp.com"

RUN sed -i '/<IfModule mod_quotatab.c>/,/<\/IfModule>/d' /etc/proftpd/proftpd.conf

RUN echo "DefaultRoot /home/admin/ftp" >> /etc/proftpd/proftpd.conf && \
    echo "Include /etc/proftpd/modules.conf" >> /etc/proftpd/proftpd.conf && \
    echo "LoadModule mod_ldap.c" >> /etc/proftpd/modules.conf && \
    echo "Include /etc/proftpd/ldap.conf" >> /etc/proftpd/proftpd.conf && \
    echo "Include /etc/proftpd/tls.conf" >> /etc/proftpd/proftpd.conf && \
    echo "PassivePorts 2100 2101" >> /etc/proftpd/proftpd.conf && \
    echo "<IfModule mod_tls.c>" >> /etc/proftpd/tls.conf && \
    echo "  TLSEngine on" >> /etc/proftpd/tls.conf && \
    echo "  TLSLog /var/log/proftpd/tls.log" >> /etc/proftpd/tls.conf && \
    echo "  TLSProtocol SSLv23" >> /etc/proftpd/tls.conf && \
    echo "  TLSRSACertificateFile /etc/ssl/certs/proftpd.crt" >> /etc/proftpd/tls.conf && \
    echo "  TLSRSACertificateKeyFile /etc/ssl/private/proftpd.key" >> /etc/proftpd/tls.conf && \
    echo "</IfModule>" >> /etc/proftpd/tls.conf && \
    echo "<Anonymous /home/admin/ftp>" >> /etc/proftpd/proftpd.conf && \
    echo "  User ftp" >> /etc/proftpd/proftpd.conf && \
    echo "  Group nogroup" >> /etc/proftpd/proftpd.conf && \
    echo "  UserAlias anonymous ftp" >> /etc/proftpd/proftpd.conf && \
    echo "  RequireValidShell off" >> /etc/proftpd/proftpd.conf && \
    echo "  MaxClients 10" >> /etc/proftpd/proftpd.conf && \
    echo "  <Directory *>" >> /etc/proftpd/proftpd.conf && \
    echo "    <Limit WRITE>" >> /etc/proftpd/proftpd.conf && \
    echo "      DenyAll" >> /etc/proftpd/proftpd.conf && \
    echo "    </Limit>" >> /etc/proftpd/proftpd.conf && \
    echo "  </Directory>" >> /etc/proftpd/proftpd.conf && \
    echo "</Anonymous>" >> /etc/proftpd/proftpd.conf && \
    echo " LoadModule mod_tls.c" >> /etc/proftpd/modules.conf

# Configuración de cuotas
RUN echo "<IfModule mod_quotatab.c>" >> /etc/proftpd/proftpd.conf && \
    echo "QuotaEngine on" >> /etc/proftpd/proftpd.conf && \
    echo "QuotaLog /var/log/proftpd/quota.log" >> /etc/proftpd/proftpd.conf && \
    echo "<IfModule mod_quotatab_file.c>" >> /etc/proftpd/proftpd.conf && \
    echo "     QuotaLimitTable file:/etc/proftpd/ftpquota.limittab" >> /etc/proftpd/proftpd.conf && \
    echo "     QuotaTallyTable file:/etc/proftpd/ftpquota.tallytab" >> /etc/proftpd/proftpd.conf && \
    echo "</IfModule>" >> /etc/proftpd/proftpd.conf && \
    echo "</IfModule>" >> /etc/proftpd/proftpd.conf

# Tablas y registros de cuotas
RUN cd /etc/proftpd
RUN cd /etc/proftpd && ftpquota --create-table --type=limit --table-path=/etc/proftpd/ftpquota.limittab && \
    ftpquota --create-table --type=tally --table-path=/etc/proftpd/ftpquota.tallytab && \
    ftpquota --add-record --type=limit --name=mario --quota-type=user --bytes-upload=20 --bytes-download=400 --units=Mb --files-upload=15 --files-download=50 --table-path=/etc/proftpd/ftpquota.limittab && \
    ftpquota --add-record --type=tally --name=mario --quota-type=user

# Configuración LDAP en /etc/proftpd/proftpd.conf
RUN echo "<IfModule mod_ldap.c>" >> /etc/proftpd/proftpd.conf && \
    echo "    LDAPLog /var/log/proftpd/ldap.log" >> /etc/proftpd/proftpd.conf && \
    echo "    LDAPAuthBinds on" >> /etc/proftpd/proftpd.conf && \
    echo "    LDAPServer ldap://${aws_instance.instancia_ldap.private_ip}:389" >> /etc/proftpd/proftpd.conf && \
    echo "    LDAPBindDN \"cn=admin,dc=lauraftp,dc=com\" \"admin_password\"" >> /etc/proftpd/proftpd.conf && \
    echo "    LDAPUsers \"dc=lauraftp,dc=com\" \"(uid=%u)\"" >> /etc/proftpd/proftpd.conf && \
    echo "</IfModule>" >> /etc/proftpd/proftpd.conf

# Configuración LDAP en /etc/proftpd/ldap.conf
RUN echo "<IfModule mod_ldap.c>" >> /etc/proftpd/ldap.conf && \
    echo "    # Dirección del servidor LDAP" >> /etc/proftpd/ldap.conf && \
    echo "    LDAPServer ${aws_instance.instancia_ldap.private_ip}" >> /etc/proftpd/ldap.conf && \
    echo "    LDAPBindDN \"cn=admin,dc=lauraftp,dc=com\" \"admin_password\"" >> /etc/proftpd/ldap.conf && \
    echo "    LDAPUsers ou=usuarios,dc=lauraftp,dc=com (uid=%u)" >> /etc/proftpd/ldap.conf && \
    echo "    CreateHome on 755" >> /etc/proftpd/ldap.conf && \
    echo "    LDAPGenerateHomedir on 755" >> /etc/proftpd/ldap.conf && \
    echo "    LDAPForceGeneratedHomedir on 755" >> /etc/proftpd/ldap.conf && \
    echo "    LDAPGenerateHomedirPrefix /home" >> /etc/proftpd/ldap.conf && \
    echo "</IfModule>" >> /etc/proftpd/ldap.conf

RUN echo "<Directory /home/admin/ftp>" >> /etc/proftpd/proftpd.conf && \
    echo "<Limit WRITE>" >> /etc/proftpd/proftpd.conf && \
    echo "  DenyUser lucia" >> /etc/proftpd/proftpd.conf && \
    echo "</Limit>" >> /etc/proftpd/proftpd.conf && \
    echo "</Directory>" >> /etc/proftpd/proftpd.conf 

EXPOSE 20 21 990 2100 2101
CMD ["sh", "-c", "chmod -R 777 /home/admin/ftp && proftpd --nodaemon"]
DOCKERFILE

docker build -t mi_proftpd .
docker run -d --name proftpd_server -p 20:20 -p 21:21 -p 990:990 -p 2100:2100 -p 2101:2101 -v /home/admin/ftp:/home/admin/ftp mi_proftpd
              EOF

  tags = {
    Name = "FTPServer"
  }
}

resource "aws_instance" "instancia_ldap" {
  ami                    = "ami-064519b8c76274859"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subred_privada_secundaria.id
  key_name               = "arwen"
  vpc_security_group_ids = [aws_security_group.sg_ldap_servidor.id]
  depends_on = [aws_nat_gateway.nat_gateway_secundaria]

user_data = <<-EOF
#!/bin/bash
sleep 30
apt-get update -y
apt-get install -y docker.io
systemctl start docker
systemctl enable docker

mkdir -p /home/admin/ldap

cat <<-EOT > /home/admin/ldap/Dockerfile

FROM osixia/openldap:1.5.0

# Variables de entorno
ENV LDAP_ORGANISATION="FTP Laura"
ENV LDAP_DOMAIN="lauraftp.com"
ENV LDAP_ADMIN_PASSWORD="admin_password"

EOT

cat <<-BOOT > /home/admin/ldap/bootstrap.ldif
# Unidad organizativa para usuarios
dn: ou=usuarios,dc=lauraftp,dc=com
objectClass: top
objectClass: organizationalUnit
ou: usuarios

# Usuario: Mario
dn: uid=mario,ou=usuarios,dc=lauraftp,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
cn: mario
sn: Lopez
uid: mario
mail: mario@lauraftp.com
userPassword: mario
uidNumber: 2001
gidNumber: 2001
homeDirectory: /home/ftp/
loginShell: /bin/bash

# Usuario: Lucia
dn: uid=lucia,ou=usuarios,dc=lauraftp,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
cn: lucia
sn: Perez
uid: lucia
mail: lucia@lauraftp.com
userPassword: lucia
uidNumber: 2002
gidNumber: 2002
homeDirectory: /home/ftp/
loginShell: /bin/bash

BOOT

cd /home/admin/ldap
docker build -t myldap .

docker run -d -p 389:389 -p 636:636 --name ldap myldap
sleep 10

docker cp bootstrap.ldif ldap:/tmp

docker exec ldap ldapadd -x -D "cn=admin,dc=lauraftp,dc=com" -w admin_password -f /tmp/bootstrap.ldif

docker exec ldap ldappasswd -x -D "cn=admin,dc=lauraftp,dc=com" -w admin_password -s "mario" "uid=mario,ou=usuarios,dc=lauraftp,dc=com"
docker exec ldap ldappasswd -x -D "cn=admin,dc=lauraftp,dc=com" -w admin_password -s "lucia" "uid=lucia,ou=usuarios,dc=lauraftp,dc=com"

docker stop ldap
docker start ldap
EOF

  tags = {
    Name = "LDAPServer"
  }
}