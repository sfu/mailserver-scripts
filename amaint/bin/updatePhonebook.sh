#!/bin/sh
/usr/local/bin/curl -k -sS "https://phonebookextract.its.sfu.ca/PhoneBook.svc/PhoneBookXml" | /usr/local/amaint/prod/bin/updtpb.pl 
