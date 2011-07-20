######################################################################
#
#	Make file to be installed in /etc/raddb/certs to enable
#	the easy creation of certificates.
#
#	See the README file in this directory for more information.
#	
#	$Id$
#
######################################################################

DH_KEY_SIZE	= 1024

#
#  Set the passwords
#
PASSWORD_CA	= `grep output_password ca.cnf | sed 's/.*=//;s/^ *//'`
PASSWORD_CLIENT	= `grep output_password client.cnf | sed 's/.*=//;s/^ *//'`
PASSWORD_SUBCA	= `grep output_password subca.cnf | sed 's/.*=//;s/^ *//'`

USER_NAME	= `grep emailAddress client.cnf | grep '@' | sed 's/.*=//;s/^ *//'`
CA_DEFAULT_DAYS = `grep default_days ca.cnf | sed 's/.*=//;s/^ *//'`

######################################################################
#
#  Make the necessary files, but not client certificates.
#
######################################################################
.PHONY: all
all: index.txt serial dh random ca subca 


.PHONY: subca
subca: subca.pem

.PHONY: client
client: client.pem

.PHONY: ca
ca: ca.der

######################################################################
#
#  Diffie-Hellman parameters
#
######################################################################
dh:
	openssl dhparam -out dh $(DH_KEY_SIZE)

######################################################################
#
#  Create a pair of new self-signed CA certificates, but use a CSR
#  for the first CA since we'll be cross signing it with second CA
#
######################################################################
#ca.key ca.pem: ca.cnf
#	openssl req -new -x509 -keyout ca.key -out ca.pem \
#		-days $(CA_DEFAULT_DAYS) -config ./ca.cnf

ca.csr ca.key: ca.cnf
	openssl req -new -out ca.csr -keyout ca.key -days $(CA_DEFAULT_DAYS) \
	-config ./ca.cnf

ca.pem: ca.csr ca.key
	openssl x509 -req -in ca.csr -signkey ca.key -out ca.pem -extfile ./ca.cnf -passin pass:$(PASSWORD_CA)

ca.der: ca.pem
	openssl x509 -inform PEM -outform DER -in ca.pem -out ca.der

ca2.key ca2.pem: ca2.cnf
	openssl req -new -x509 -keyout ca2.key -out ca2.pem \
		-days $(CA_DEFAULT_DAYS) -config ./ca2.cnf

ca2.der: ca2.pem
	openssl x509 -inform PEM -outform DER -in ca2.pem -out ca2.der




######################################################################
#
#  Create a new subca certificate, signed by CA 1.
#
######################################################################
subca.csr subca.key: subca.cnf
	openssl req -new  -out subca.csr -keyout subca.key -config ./subca.cnf

subca.crt: subca.csr ca.key ca.pem
	openssl ca -batch -keyfile ca.key -cert ca.pem -in subca.csr  -key $(PASSWORD_CA) -out subca.crt -config ./subca.cnf

subca.p12: subca.crt
	openssl pkcs12 -export -in subca.crt -inkey subca.key -out subca.p12  -passin pass:$(PASSWORD_SUBCA) -passout pass:$(PASSWORD_SUBCA)

subca.pem: subca.p12
	openssl pkcs12 -in subca.p12 -out subca.pem -passin pass:$(PASSWORD_SUBCA) -passout pass:$(PASSWORD_SUBCA)

.PHONY: subca.vrfy
subca.vrfy: ca.pem
	openssl verify -CAfile ca.pem subca.pem

######################################################################
#
#  Create a new client certificate, signed by the the subca issuer
#  certificate.
#
######################################################################
client.csr client.key: client.cnf
	openssl req -new  -out client.csr -keyout client.key -config ./client.cnf

client.crt: client.csr ca.pem ca.key
	openssl ca -batch -keyfile subca.key -cert subca.pem -in client.csr  -key $(PASSWORD_SUBCA) -out client.crt -config ./client.cnf

client.p12: client.crt
	openssl pkcs12 -export -in client.crt -inkey client.key -out client.p12  -passin pass:$(PASSWORD_CLIENT) -passout pass:$(PASSWORD_CLIENT)

client.pem: client.p12
	openssl pkcs12 -in client.p12 -out client.pem -passin pass:$(PASSWORD_CLIENT) -passout pass:$(PASSWORD_CLIENT)
	cp client.pem $(USER_NAME).pem

.PHONY: client.vrfy
client.vrfy: server.pem client.pem 
	c_rehash .
	openssl verify -CApath . client.pem

######################################################################
#
#  Miscellaneous rules.
#
######################################################################
index.txt:
	@if [ -e index.txt ] ; then \
		rm index.txt; \
	fi
	@touch index.txt

serial:
	@if [ -e serial ] ; then \
		rm serial; \
	fi
	@echo '01' > serial
	@echo '01' > serial2

random:
	#@if [ -c /dev/urandom ] ; then \
	#	dd if=/dev/urandom of=./random count=10 >/dev/null 2>&1; \
	#else \
	#	date > ./random; \
	#fi
	date > ./random; 

print:
	openssl x509 -text -in server.crt

printca:
	openssl x509 -text -in ca.pem

clean:
	@rm -f *~ *old client.csr client.key client.crt client.p12 client.pem

#
#	Make a target that people won't run too often.
#
destroycerts:
	rm -f *~ dh *.csr *.crt *.p12 *.der *.pem *.key index.txt* \
			serial* random *\.0 *\.1
