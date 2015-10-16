#!/usr/local/bin/perl -w
open( MSG, "|/opt/mail/maillist2/bin/util/mlqtest.pl tws-nonfic09 3.5" );
    print MSG "From slegge\@canadawide.com Fri May 15 15:26:54 2001\n".
"Return-Path: slegge\@canadawide.com\n".
"Message-Id: 5f239daf0902170743q195767e6ha7a064b51f231196\@mail.gmail.com\n".
"Date: Fri, 30 Mar 2001 13:26:54 -0700\n".
"From: slegge\@canadawide.com\n".
"Subject: Testing send n".
"To: tws-nonfic09\@sfu.ca\n".
"X-IMAPbase: 1165447632 1\n\n".
"test\n";

close MSG;
exit 0;

