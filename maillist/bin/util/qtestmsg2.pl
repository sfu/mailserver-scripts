#!/usr/bin/perl -w
open( MSG, "|./mlqtest.pl ic-info 3.5" );
    print MSG "From robert Fri May 15 15:26:54 2001\n".
"Return-Path: <robert\@sfu.ca>\n".
"Message-Id: 119823457912384\n".
"Date: Fri, 30 Mar 2001 13:26:54 -0700\n".
"From: robert\@sfu.ca\n".
"Subject: Testing send by allowed\n".
"To: ic-info\@sfu.ca\n".
"X-IMAPbase: 1165447632 1\n\n".
"test\n";

close MSG;
exit 0;

