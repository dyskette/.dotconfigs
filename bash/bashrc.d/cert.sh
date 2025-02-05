function create_self_signed_certificate() {
		echo -e '\033[0;32m:::Creating certificates...\033[0m'
		openssl req -config $HOME/.bashrc.d/cert.conf -new -x509 -sha256 -newkey rsa:2048 -nodes -keyout localhost.key -days 3650 -out localhost.pem
		openssl pkcs12 -export -out localhost.pfx -inkey localhost.key -in localhost.pem
}

function trust_self_signed_certificate() {
		if [[ "$(awk -F= '/^NAME/{print $2}' /etc/os-release)" == '"Ubuntu"' ]]; then
				echo -e '\033[0;32m:::Installing certificates for Ubuntu...\033[0m'
				sudo cp localhost.pem /usr/local/share/ca-certificates/localhost.crt
				sudo update-ca-certificates
		elif [[ "$(awk -F= '/^NAME/{print $2}' /etc/os-release)" == '"Fedora Linux"' ]]; then
				echo -e '\033[0;32m:::Installing certificates for Fedora...\033[0m'
				sudo cp localhost.pem /etc/pki/ca-trust/source/anchors/localhost.pem
				sudo update-ca-trust
		fi
}
