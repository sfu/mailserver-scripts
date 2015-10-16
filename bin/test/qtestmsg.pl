#!/usr/local/bin/perl -w
open( MSG, "|/opt/mail/maillist2/bin/test/mlqtest.pl ic-info 3.5" );
    print MSG "From <robert\@sfu.ca> Fri May 15 15:26:54 2001\n".
"Return-Path: robert\@sfu.ca\n".
"Message-Id: 5f239daf0902170743q195767e6ha7a064b51f231199\@sfu.ca\n".
"Date: Fri, 30 Mar 2001 13:26:54 -0700\n".
"From: <robert\@sfu.ca>\n".
"Subject: Testing send Testing send Testing sendë Testing send \n".
"To: ic-info\@sfu.ca\n".
"X-IMAPbase: 1165447632 1\n\n".
"test\n";

close MSG;
exit 0;

