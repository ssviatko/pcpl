#!/usr/bin/perl

#
# A fun, simple, and useful Perl script to prove to potential employers that I know Perl.
#
#    Stephen Sviatko (ssviatko@gmail.com)
#    (C) 2017, 2018 Good Neighbors LLC - Unlimited site license granted as long
#    as this script remains unmodified and the original author is credited.
#
# Requires perl (any version that supports sockets), netcat.
#
# This is a simple chat system reminiscent of Diversi-Dial on an Apple //.
# To use this program: Under Linux, type chmod +x pc.pl and ./pc.pl in one window,
# Type "nc localhost 9734" (or whatever port pc.pl is listening on) in another window.
# Make as many connections to the machine running pc.pl as desired, up to $MAX_PEERS.
# Type /help for a list of commands once you are connected with netcat.
# Use of the /exec command is strongly cautioned if pc.pl is running in a root session!
#

use warnings;
use strict;

use IO::Socket::INET;
use Fcntl;

my $socket;

$socket = new IO::Socket::INET (
	LocalHost => inet_ntoa(INADDR_ANY),
	LocalPort => '9734',
	Proto => 'tcp',
	Listen => 5,
	ReuseAddr => 1
	) or die "ERROR in Socket Creation : $!\n";

my $result;
my $flags;

$flags = fcntl($socket, F_GETFL, 0) or die "Can't fcntl F_GETFL : $!\n";
$result = fcntl($socket, F_SETFL, $flags | O_NONBLOCK) or die "Can't fcntl F_SETFL : $!\n";

my $version_string = '--- Pocket Chat v1.01 By Stephen Sviatko (ssviatko@gmail.com) - 28/Jun/2018';
my $MAX_PEERS = 64;
my @peer_list;
my @peer_names;

print "Clearing slot data...\n";

for (my $i = 0; $i < $MAX_PEERS; ++$i) {
	$peer_list[$i] = undef;
	$peer_names[$i] = undef;
}

sub get_slot {
	my $ret = -1;
	my $client = shift;
	for (my $i = 0; $i < $MAX_PEERS; ++$i) {
		if (not defined $peer_list[$i]) {
			$peer_list[$i] = $client;
			$ret = $i;
			last;
		}
	}
	return $ret;
}

sub bcast {
	my $bcast_msg = shift;
	print "$bcast_msg\n";
	for (my $i = 0; $i < $MAX_PEERS; ++$i) {
		if (defined $peer_list[$i]) {
			my $client = $peer_list[$i];
			if ($client->connected()) {
				print $client "$bcast_msg\n";
			}
		}
	}
}

sub scrub {
	for (my $i = 0; $i < $MAX_PEERS; ++$i) {
		if (defined $peer_list[$i]) {
			my $client = $peer_list[$i];
			if (not $client->connected()) {
				$peer_list[$i] = undef;
				$peer_names[$i] = undef;
				my $bc = "[$i - user has disconnected]";
				bcast($bc);
			}
		}
	}
}

sub who_listing {
	my $cur_peer = shift;
	print $cur_peer "--- Users online\n";
	for (my $i = 0; $i < $MAX_PEERS; ++$i) {
		if (defined $peer_list[$i]) {
			my $cur_name;
			if (defined $peer_names[$i]) {
				$cur_name = $peer_names[$i];
			} else {
				$cur_name = "none";
			}
			print $cur_peer "$i/$cur_name\n";
		}
	}
}

sub whoami_listing {
	my $cur_peer = shift;
	my $cur_slot = shift;
	my $cur_name = shift;
	print $cur_peer "--- You are\n$cur_slot/$cur_name\n";
}

sub help_listing {
	my $cur_peer = shift;
	print $cur_peer "--- Commands\n";
	print $cur_peer "/help           : This screen\n";
	print $cur_peer "/ver            : Build info\n";
	print $cur_peer "/quit           : Disconnect from teleconference\n";
	print $cur_peer "/who            : Who is online\n";
	print $cur_peer "/whoami         : Display info about your connection\n";
	print $cur_peer "/name <handle>  : Set username\n";
	print $cur_peer "/p0 <message>   : Send private message to user on slot 0\n";
	print $cur_peer "<message>       : Send public message to all users\n";
	print $cur_peer "--- Admin Commands\n";
	print $cur_peer "/k0 <message>   : Forcibly disconnect user on slot 0, with private message\n";
	print $cur_peer "/exec <command> : Execute <command> on host\n";
	print $cur_peer "/down           : Down teleconference immediately and exit script\n";
}

sub exec_command {
	my $cur_peer = shift;
	my $cur_cmd = shift;
	print $cur_peer "--- Executing command\n$cur_cmd\n";
	my $result = `$cur_cmd`;
	print $cur_peer "--- Command returned\n$result";
}

sub serve {
	for (my $i = 0; $i < $MAX_PEERS; ++$i) {
		if (defined $peer_list[$i]) {
			my $cur_peer = $peer_list[$i];
			my $cur_name;
			if (defined $peer_names[$i]) {
				$cur_name = $peer_names[$i];
			} else {
				$cur_name = "none";
			}
			my $data = <$cur_peer>;
			if (defined $data) {
				chomp($data);
				print "-$i: $data\n";
				if ($data eq "/quit") {
					$cur_peer->close();
				} elsif ($data eq "/down") {
					exit;
				} elsif ($data eq "/who") {
					who_listing($cur_peer);
				} elsif ($data eq "/whoami") {
					whoami_listing($cur_peer, $i, $cur_name);
				} elsif ($data eq "/help") {
					help_listing($cur_peer);
				} elsif ($data eq "/ver") {
					print $cur_peer "$version_string\n";
				} elsif ($data =~ /^\/exec (.*$)/) {
					$1 =~ s/^\s+//;
					exec_command($cur_peer, $1);
				} elsif (substr($data, 0, 5) eq "/name" ) {
					$peer_names[$i] = substr($data, 6, length($data) - 5);
					my $bc = "[$i - user is now known as: $peer_names[$i]]";
					bcast($bc);
				} elsif ($data =~ /^\/k(\d+) *(.*$)/) {
					$2 =~ s/^\s+//;
					my $kill_user = $peer_list[$1];
					if (defined $kill_user) {
						if ($kill_user->connected()) {
							print $kill_user "--- You have been removed from the teleconference.\n";
							print $kill_user "--- Reason: $2\n";
							$kill_user->close();
						}
					} else {
						print $cur_peer "[$1 - No user online]\n";
					}
				} elsif ($data =~ /^\/p(\d+) *(.*$)/) {
					$2 =~ s/^\s+//;
					my $priv_user = $peer_list[$1];
					if (defined $priv_user) {
						if ($priv_user->connected()) {
							print $priv_user "[P$i/$cur_name] $2\n";
						}
					} else {
						print $cur_peer "[$1 - No user online]\n";
					}
				} else {
					my $bc = '[' . $i . '/' . $cur_name . '] ' . $data;
					bcast($bc);
				}
			}
		}
	}
}

sub attempt_accept {
	my $client_socket = $socket->accept();
	if (defined $client_socket) {
		my $flags = fcntl($client_socket, F_GETFL, 0) or die "Can't fcntl F_GETFL client socket : $!\n";
		my $result = fcntl($client_socket, F_SETFL, $flags | O_NONBLOCK) or die "Can't fcntl F_SETFL client socket : $!\n";
		my $peer_addr = $client_socket->peerhost();
		my $peer_port = $client_socket->peerport();
		my $slot = get_slot($client_socket);
		if ($slot >= 0) {
			my $bc = "[$slot - Accepted connection from $peer_addr:$peer_port]";
			bcast($bc);
			print $client_socket "I am acknowledging you.\n";
		} else {
			print "Refused connection from $peer_addr:$peer_port (no connection slots available).\n";
			print $client_socket "No more connection slots available. Buzz off!\n";
			$client_socket->close();
		}
	}
}

print "Listening on TCP port 9734...\n";

while (1) {
	attempt_accept;
	scrub;
	serve;
	sleep(1);
}

