#!/bin/bash

SUMDIR=/path/to/dir/for/signature/storage
BASEDIR=/path/to/log/directory
# TSA URL to use, also download the relevant cacert+tsa.crt for this
TSAURL=https://freetsa.org/tsr
# By default, do this for directory from 3 days ago,
# as we compress the logfiles after 2 days, so after this, there shouldn't be
# any more changes. You can do this after 1 day, if you don't compress, but
# checksumming will take significantly longer, and you need more storage.
SUMDATE="${1:-3 days ago}"
DATE=$(date -d "$SUMDATE" +%Y/%m/%d)
SUMFILE=$(date -d "$SUMDATE" +%Y%m%d.sha256sum )

cd ${SUMDIR}

if [ -r ${SUMDIR}/${SUMFILE} ]; then
	echo "Checksum file already exists"
else
	echo "Checksumming files for ${DATE}"
  # Change fileglobs here for however you specify/store your logfiles
  # we do base/envname/YYYY/MM/DD/HOSTNAME/SERVICE.log.gz
	sha256sum ${BASEDIR}/*/${DATE}/*/* > ${SUMDIR}/${SUMFILE}
fi

if [ -r ${SUMDIR}/${SUMFILE}.sig ]; then
	echo "Signature already created"
else
	echo "Signing checksum file for ${DATE}"
	gpg -bs ${SUMDIR}/${SUMFILE}
fi

if [ -r ${SUMDIR}/${SUMFILE}.tsq ]; then
	echo "Timestamp query file is present"
else
	echo "Creating timestamp query file"
	openssl ts -query -data ${SUMDIR}/${SUMFILE} -no_nonce -sha512 -cert -out ${SUMDIR}/${SUMFILE}.tsq
fi

if [ -r ${SUMDIR}/${SUMFILE}.tsr ]; then
	echo "Timestamp result file is present"
else
	echo "Timestamping file using freetsa.org"
	curl -H "Content-Type: application/timestamp-query" \
		--data-binary @${SUMDIR}/${SUMFILE}.tsq \
		 https://freetsa.org/tsr > ${SUMDIR}/${SUMFILE}.tsr
fi

if [ -r ${SUMDIR}/${SUMFILE}.tsr ]; then
	echo "Timestamp result is present, verifying both ways"
	openssl ts -reply -in ${SUMDIR}/${SUMFILE}.tsr -text
	openssl ts -verify -data ${SUMDIR}/${SUMFILE} \
		-in ${SUMDIR}/${SUMFILE}.tsr \
		-CAfile cacert.pem -untrusted tsa.crt
	openssl ts -verify -in ${SUMDIR}/${SUMFILE}.tsr \
		-queryfile ${SUMDIR}/${SUMFILE}.tsq \
		 -CAfile cacert.pem -untrusted tsa.crt
fi
