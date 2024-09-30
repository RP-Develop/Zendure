# FHEM Modul für Zendure Login Daten 
package main;

use strict;
use warnings;

use HttpUtils;
use JSON;
use Data::Dumper;
use MIME::Base64;

use constant VERSION 			=> "v0.0.2";

my %server = (
	global => "v2",
	Global => "v2",
	v2 => "v2",
	eu => "eu",
	EU => "eu"
);


sub Zendure_Initialize($) {
	my ($hash) = @_;

	# Definieren von FHEM-Funktionen
	$hash->{DefFn}	= "Zendure_Define";
	$hash->{SetFn}	= "Zendure_Set";
	$hash->{GetFn}	= "Zendure_Get";
}

# Definition des Geräts in FHEM
sub Zendure_Define($$) {
	my ($hash, $def) = @_;
	my @args = split("[ \t][ \t]*", $def);

	return "Usage: define <name> Zendure <user> <password> <server>" if (int(@args) != 5);

	my $name		= $args[0];
	my $username	= Zendure_encrypt($args[2]);
	my $password	= Zendure_encrypt($args[3]);
	$hash->{server}	= $server{$args[4]};

	$hash->{VERSION}			= VERSION;
	$hash->{DEF} = "$username $password $hash->{server}";
	$hash->{helper}{username}	= $username;
	$hash->{helper}{password} 	= $password ;
	$hash->{NAME}				= $name;
	$hash->{STATE}				= 'initialized';

	readingsSingleUpdate($hash, 'state', 'initialized', 1 );

	return undef;
}


sub Zendure_Set($$@) {
	my ($hash, $name, $cmd, @args) = @_;

	my $list = "Login:noArg";

	if ($cmd eq "Login") {

		Zendure_getAccessToken($hash);

		readingsSingleUpdate($hash, 'state', $cmd, 1 );

		return undef;
	}

	return "Unknown argument $cmd, choose one of $list";
}


sub Zendure_getAccessToken{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $url = "https://app.zendure.tech/".$hash->{server}."/auth/app/token";

	my $username	= Zendure_decrypt($hash->{helper}{username});
	my $password	= Zendure_decrypt($hash->{helper}{password});
	
	my $auth = "Basic ".encode_base64("$username:$password", ''); # '' verhindert ein NewLine

	my $body = {
		password	=> $password,
		account		=> $username,
		appId		=> '121c83f761305d6cf7b',
		appType		=> 'iOS',
		grantType	=> 'password',
		tenantId	=> ''
	};

	# HTTP POST Anfrage senden
	my $json_body = encode_json($body);
	
	my $header    = {
		"Content-Type"		=> 'application/json',
		"Accept-Language"	=> 'de-DE',
		"appVersion"		=> '4.3.1',
		"User-Agent"		=> 'Zendure/4.3.1 (iPhone; iOS 14.4.2; Scale/3.00)',
		"Accept"			=> '*/*',
		"Authorization"		=> $auth,
		"Blade-Auth"		=> 'bearer (null)',
	};

	my $param = {
		"url"			=> $url,
		"method"		=> "POST",
		"timeout"		=> 5,
		"header"		=> $header, 
		"data"			=> $json_body, 
		"hash"			=> $hash,
		"command"		=> "getAccessToken",
		"callback"		=> \&Zendure_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Request> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n".
		"## Body ##############\n".$json_body."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}


sub Zendure_getDeviceList{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $url = "https://app.zendure.tech/".$hash->{server}."/productModule/device/queryDeviceListByConsumerId";

	my $body = {};

	# HTTP POST Anfrage senden
	my $json_body = encode_json($body);
	
	my $bladeAuth = "bearer ".$hash->{helper}{accessToken};
	
	my $header    = {
		"Content-Type"		=> 'application/json',
		"Accept-Language"	=> 'de-DE',
		"appVersion"		=> '4.3.1',
		"User-Agent"		=> 'Zendure/4.3.1 (iPhone; iOS 14.4.2; Scale/3.00)',
		"Accept"			=> '*/*',
		"Authorization"		=> "Basic Q29uc3VtZXJBcHA6NX4qUmRuTnJATWg0WjEyMw==",
		"Blade-Auth"		=> $bladeAuth
	};

	my $param = {
		"url"			=> $url,
		"method"		=> "POST",
		"timeout"		=> 5,
		"header"		=> $header, 
		"data"			=> $json_body, 
		"hash"			=> $hash,
		"command"		=> "getDeviceList",
		"callback"		=> \&Zendure_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Request> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n".
		"## Body ##############\n".$json_body."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}

sub Zendure_parseRequestAnswer {
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	my $responseData;

	my $error	= "not defined";
	my $message	= "not defined";
	my $statusCode	= "not defined";

	if($err ne ""){
		Log3 $name, 1, $name.": error while HTTP requesting ".$param->{url}." - $err"; 
		readingsSingleUpdate($hash, 'state', 'error', 1 );
		return undef;
	}
	elsif($data ne ""){
		Log3 $name, 5, $name.": <parseRequestAnswer> URL:".$param->{url}." returned data:\n".
			"## HTTP-Statuscode ###\n".$param->{code} ."\n".
			"## Data ##############\n".$data."\n".
			"## Header ############\n".$param->{httpheader}."\n";
  
		# $param->{code} auswerten?
		unless (($param->{code} == 200) || ($param->{code} == 400)){
			Log3 $name, 1, $name.": error while HTTP requesting ".$param->{url}." - code: ".$param->{code}; 
			readingsSingleUpdate($hash, 'state', 'error', 1 );
			return undef;
		}

		# testen ob JSON OK ist
		if($data =~ m/\{.*\}/s){
			eval{
				$responseData = decode_json($data);
				Zendure_convertBool($responseData);
			};
			if($@){
				my $error = $@;
				$error =~ m/^(.*?)\sat\s(.*?)$/;
				Log3 $name, 1, $name.": error while HTTP requesting of command '".$param->{command}."' - Error while JSON decode: $1 ";
				Log3 $name, 5, $name.": <parseRequestAnswer> JSON decode at: $2";
				readingsSingleUpdate($hash, 'state', 'error', 1 );
				return undef;
			}
			# testen ob Referenz vorhanden
			if(ref($responseData) ne 'HASH') {
				Log3 $name, 1, $name.": error while HTTP requesting of command '".$param->{command}."' - Error, response isn't a reference!";
				readingsSingleUpdate($hash, 'state', 'error', 1 );
				return undef;
			}
		}                                                       

		# bei code 400 kommt evtl. erweiterter Hinweise im JSON
		if ($param->{code} == 400){
			if($responseData->{msg}){
				Log3 $name, 1, $name.": <Zendure_connect> error while HTTP requesting ".$param->{url}." - code: ".$param->{code}." - msg: ".$responseData->{msg}; 
			}
			else{
				Log3 $name, 1, $name.": <Zendure_connect> error while HTTP requesting ".$param->{url}." - code: ".$param->{code}; 
			}
			readingsSingleUpdate($hash, 'state', 'error', 1 );
			return undef;
		}		                                                      

		if($param->{command} eq "getAccessToken") { 
			$hash->{helper}{auth} = $responseData;

			$hash->{helper}{accessToken} = $responseData->{data}{accessToken};
			$hash->{helper}{userId} = $responseData->{data}{userId};
			$hash->{helper}{iotUrl} = $responseData->{data}{iotUrl}.":1883";
	 		$hash->{helper}{iotUserName} = $responseData->{data}{iotUserName};
	 		$hash->{helper}{iotPassword} = decode_base64((($hash->{server} eq "v2") ? "b0sjUENneTZPWnhk" : "SDZzJGo5Q3ROYTBO"));

			readingsBeginUpdate($hash); 	
	 			readingsBulkUpdate($hash, "MQTT_accessToken", $hash->{helper}{accessToken});
				readingsBulkUpdate($hash, "MQTT_userId", $hash->{helper}{userId});
				readingsBulkUpdate($hash, "MQTT_iotUrl", $hash->{helper}{iotUrl});
				readingsBulkUpdate($hash, "MQTT_iotUserName", $hash->{helper}{iotUserName});
				readingsBulkUpdate($hash, "MQTT_iotPassword", $hash->{helper}{iotPassword});
			readingsEndUpdate($hash, 1);

			readingsSingleUpdate($hash, 'state', 'Access Token successful loaded!', 1 );
			
			# wenn OK, dann Liste holen
			Zendure_getDeviceList($hash);
			
		}
		elsif($param->{command} eq "getDeviceList"){
			$hash->{helper}{devices} = $responseData;
		
			$hash->{devices} = scalar @{$responseData->{data}};
			
			$hash->{helper}{productKey} = $responseData->{data}[0]{productKey};
			$hash->{helper}{deviceKey} = $responseData->{data}[0]{deviceKey};
			
			$hash->{helper}{subscriptions} = "";
			
			my $k = 0;
			my $subscriptions = "";
			for my $i (0 .. ($hash->{devices}-1)){
				$subscriptions = "/".$responseData->{data}[$i]{productKey}."/".$responseData->{data}[$i]{deviceKey}."/# iot/".$responseData->{data}[$i]{productKey}."/".$responseData->{data}[$i]{deviceKey}."/#";
				$hash->{helper}{subscriptions} .= $subscriptions." \n";
				$k = $i + 1;
				readingsBeginUpdate($hash); 	
					readingsBulkUpdate($hash, "Device_".$k."_productKey", $responseData->{data}[$i]{productKey});
					readingsBulkUpdate($hash, "Device_".$k."_deviceKey", $responseData->{data}[$i]{deviceKey});
					readingsBulkUpdate($hash, "Device_".$k."_snNumber", $responseData->{data}[$i]{snNumber});
					readingsBulkUpdate($hash, "Device_".$k."_productName", $responseData->{data}[$i]{productName});
					readingsBulkUpdate($hash, "Device_".$k."_name", $responseData->{data}[$i]{name});
					readingsBulkUpdate($hash, "Device_".$k."_subscriptions", $subscriptions);
				readingsEndUpdate($hash, 1);
			}
			
			readingsSingleUpdate($hash, 'state', 'Device List successful loaded!', 1 );

		}
		else{
			Log3 $name, 5, $name.": <parseRequestAnswer> unhandled command $param->{command}";
		}
		return undef;
	}
	Log3 $name, 1, $name.": error while HTTP requesting URL:".$param->{url}." - no data!";
	return undef;
}

sub Zendure_Get {
	my ($hash, $name, $opt, @args) = @_;

	return "\"get $name\" needs at least one argument" unless(defined($opt));

	Log3 $name, 5, $name.": <Get> called for $name : msg = $opt";

	my $dump;
	my $usage = "Unknown argument $opt, choose one of AccessToken:noArg DeviceList:noArg ConfigProposal:noArg Account:noArg";
	
	if ($opt eq "AccessToken"){
		if(defined($hash->{helper}{auth})){
	        if(%{$hash->{helper}{auth}}){
	        	Zendure_convertBool($hash->{helper}{auth});
			    local $Data::Dumper::Deepcopy = 1;
				$dump = Dumper($hash->{helper}{auth});
				$dump =~ s{\A\$VAR\d+\s*=\s*}{};
	        	return "stored data:\n".$dump;
	        }
	    }
		return "No data available: $opt";	
	} 
	elsif($opt eq "DeviceList"){
		if(defined($hash->{helper}{devices})){
			if(%{$hash->{helper}{devices}}){
				Zendure_convertBool($hash->{helper}{devices});
				local $Data::Dumper::Deepcopy = 1;
				$dump = Dumper($hash->{helper}{devices});
				$dump =~ s{\A\$VAR\d+\s*=\s*}{};
				return "stored data:\n".$dump;
			}
		}
		return "No data available: $opt";
	}
	elsif($opt eq "Account"){
		my $username = $hash->{helper}{username};
		my $password = $hash->{helper}{password};

		return 'no username set' if( !$username );
		return 'no password set' if( !$password );

		$username = Zendure_decrypt( $username );
		$password = Zendure_decrypt( $password );

		return "username: $username\npassword: $password";
	}
	elsif($opt eq "ConfigProposal"){
		if(defined($hash->{helper}{auth}) && defined($hash->{helper}{devices})){
			if((%{$hash->{helper}{auth}}) && (%{$hash->{helper}{devices}})){
				my $text = "Config Proposal:\n";
				$text .= "\n";
				$text .= "Fhem MQTT automatic configuration with loaded ZendureUtil.pm\n";
				$text .= "\n";
				$text .= "define &lt\;name&gt\; MQTT2_CLIENT &lt\;name&gt\;\n";
				$text .= "attr &lt\;name&gt\; username ".Zendure_decrypt($hash->{helper}{username})."\n";;
				$text .= "attr &lt\;name&gt\; connectFn \{use ZendureUtils;;Zendure_connect(\$NAME,".'"global"'.",1)\‚}\n";
				$text .= "set &lt\;name&gt\; password ".Zendure_decrypt($hash->{helper}{password})."\n";
				$text .= "\n";
				$text .= "\n";
				$text .= "\n";
				$text .= "Fhem MQTT own configuration:\n";
				$text .= "\n";
				$text .= "MQTT2_CLIENT\n";
				$text .= "\n";
				$text .= "define &lt\;name&gt\; MQTT2_CLIENT $hash->{helper}{iotUrl}\n";
				$text .= "set &lt\;name&gt\; password $hash->{helper}{iotPassword}\n";
				$text .= "attr &lt\;name&gt\; username $hash->{helper}{iotUserName}\n";
				$text .= "attr &lt\;name&gt\; clientId $hash->{helper}{accessToken}\n";
				$text .= "attr &lt\;name&gt\; autocreate no\n";
				$text .= "attr &lt\;name&gt\; subscriptions $hash->{helper}{subscriptions}\n";
				$text .= "\n";
				$text .= "\n";
				$text .= "MQTT2_DEVICE - only the first device!\n";
				$text .= "\n";
				$text .= "define &lt\;name&gt\; MQTT2_DEVICE &lt\;name of MQTT2_CLIENT&gt\;\n";
				$text .= "attr &lt\;name&gt\; IODev &lt\;name of MQTT2_CLIENT&gt\; \n";
				$text .= "attr &lt\;name&gt\; readingList &lt\;follow lines&gt\; \n";
				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/properties/report:.* { json2nameValue(\$EVENT, 'properties_report_', \$JSONMAP) }\n";
				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/event/device:.* { json2nameValue(\$EVENT, 'event_device_', \$JSONMAP) }\n";
				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/event/error:.* { json2nameValue(\$EVENT, 'event_error_', \$JSONMAP) }\n";
				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/properties/read/reply:.* { json2nameValue(\$EVENT, 'properties_read_reply_', \$JSONMAP) }\n";
				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/properties/write/reply:.* { json2nameValue(\$EVENT, 'properties_write_reply_', \$JSONMAP) }\n";
				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/connected:.* { json2nameValue(\$EVENT, 'connected_', \$JSONMAP) }\n";
				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/firmware/report:.* { json2nameValue(\$EVENT, 'firmware_report_', \$JSONMAP) }\n";
				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/time-sync:.* { json2nameValue(\$EVENT, 'time-sync_', \$JSONMAP) }\n";
				$text .= ".*iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/properties/read:.* { json2nameValue(\$EVENT, 'iot_properties_read_', \$JSONMAP) }\n";
				$text .= ".*iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/properties/write:.* { json2nameValue(\$EVENT, 'iot_properties_write_', \$JSONMAP) }\n";
				$text .= ".*iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/time-sync/reply:.* { json2nameValue(\$EVENT, 'iot_time-sync_reply_', \$JSONMAP) }\n";
				$text .= "attr &lt\;name&gt\; setList &lt\;follow lines as example&gt\; \n";
				$text .= "Output:100,200,300,400,500,600 iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/write {"properties":{"outputLimit"'.":\$EVTPART1}} \n";
				$text .= "Update:noArg iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/read {"properties":["getAll"]}'." \n";
				$text .= "Bypass:0,1,2 iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/write {"properties":{"passMode"'.":\$EVTPART1}} \n";
				$text .= "autoRecover:0,1 iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/write {"properties":{"autoRecover"'.":\$EVTPART1}} \n";
				$text .= "\n";
				$text .= "\n";
				$text .= "\n";
				$text .= "Mosquitto Bridge configuration:\n";
				$text .= "\n";
				$text .= "connection Zendure_Global\n";
				$text .= "remote_username $hash->{helper}{iotUserName}\n";
				$text .= "remote_password $hash->{helper}{iotPassword}\n";
				$text .= "clientid $hash->{helper}{accessToken}\n";
				$text .= "topic # in 0 Zendure-Global/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/ /".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/\n";
				$text .= "topic # both 0 Zendure-Global/iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/ iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/\n";
				$text .= "\n";
				$text .= "Configuration of MQTT2_DEVICE similar to above, but only with the beginning of the topic as 'Zendure-Global/...'.\n";
				$text .= "\n";
				return $text;
			}
		}
		return "No data available: $opt";
	}
	return $usage; 
}

# Convert Bool #################################################################

sub Zendure_convertBool {

	local *_convert_bools = sub {
		my $ref_type = ref($_[0]);
		if ($ref_type eq 'HASH') {
			_convert_bools($_) for values(%{ $_[0] });
		}
		elsif ($ref_type eq 'ARRAY') {
			_convert_bools($_) for @{ $_[0] };
		}
		elsif (
			   $ref_type eq 'JSON::PP::Boolean'           # JSON::PP
			|| $ref_type eq 'Types::Serialiser::Boolean'  # JSON::XS
		) {
			$_[0] = $_[0] ? 1 : 0;
		}
		else {
			# Nothing.
		}
	};

	&_convert_bools;

}

# Password Crypt ###############################################################

sub Zendure_encrypt {
  	my ($decoded) = @_;
  	my $key = getUniqueId();
  	my $encoded;

  	return $decoded if( $decoded =~ /crypt:/ );

  	for my $char (split //, $decoded) {
    	my $encode = chop($key);
    	$encoded .= sprintf("%.2x",ord($char)^ord($encode));
    	$key = $encode.$key;
  	}

  	return 'crypt:'.$encoded;
}

sub Zendure_decrypt {
  	my ($encoded) = @_;
  	my $key = getUniqueId();
  	my $decoded;

  	return $encoded if( $encoded !~ /crypt:/ );
  
  	$encoded = $1 if( $encoded =~ /crypt:(.*)/ );

  	for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
    	my $decode = chop($key);
    	$decoded .= chr(ord($char)^ord($decode));
    	$key = $decode.$key;
  	}

  	return $decoded;
}


1;
