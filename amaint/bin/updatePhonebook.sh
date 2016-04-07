#!/bin/sh
/usr/bin/curl -k -sS "https://phonebookextract.its.sfu.ca/PhoneBook.svc/PhoneBookXml" | `dirname $0`/updtpb.pl
