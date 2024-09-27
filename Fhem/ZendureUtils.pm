##############################################
# $Id$
use strict;
use warnings;

#
# Usage:
#   define Zendure MQTT2_CLIENT Zendure
#   attr Zendure username Username (from 2. Zendure account)
#   attr Zendure connectFn {use ZendureUtils;;Zendure_connect($NAME,"global",1)}
#   set Zendure password Password (from 2. Zendure account)
# 
# Second parameter Global|global|v2 -> if used the global account, eu|EU -> if used the eu server
# 
# If the last parameter to Zendure_connect is 1, devices will be autocreated
# 
# 
# 
# 
# 
# 

use HttpUtils;
use JSON;
use Data::Dumper;
use MIME::Base64;

my %server = (
	global => "v2",
	Global => "v2",
	v2 => "v2",
	eu => "eu",
	EU => "eu"
);

# Verbindung aufbauen 
sub Zendure_connect($$;$$) {
	my ($name, $type, $autocreate, $noToCheck) = @_;
	my $hash = $defs{$name}; 

	# verzögert das nächste connect, Code 1:1 übernommen vom LandroidUtils.pm
	if(!$noToCheck && $hash->{".CONNECT_TO"} &&
		gettimeofday() < $hash->{".CONNECT_TO"}) {
		delete($hash->{inConnectFn});
		$readyfnlist{"$name.$hash->{DeviceName}"} = $hash;
		return;
	}
	$hash->{".CONNECT_TO"} = gettimeofday()+AttrVal($name,"nextOpenDelay",10);
	
	return Log3 $name, 1, $name.": <Zendure_connect> no such definition" if(!$hash);
	return Log3 $name, 1, $name.": <Zendure_connect> unknown server type '$type'" if(!$server{$type});
	
	$hash->{version} = "Zendure Connect v0.0.1";
	$hash->{server} = $server{$type};
	$hash->{autocreate} = $autocreate ? 1 : 0;
	
	Zendure_connect_getAccessToken($hash);
}

# Token holen
sub Zendure_connect_getAccessToken{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $url = "https://app.zendure.tech/".$hash->{server}."/auth/app/token";

	my $user	    = AttrVal($name, "username", "");
	my $password	= getKeyValue($name); 	
	
    return Log3 $name, 1, $name.": <Zendure_connect> no username attribute" if(!$user);
    return Log3 $name, 1, $name.": <Zendure_connect> no password set" if(!$password);
	
	my $auth = "Basic ".encode_base64("$user:$password", ''); # '' verhindert ein NewLine

	my $body = {
		password	=> $password,
		account		=> $user,
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
		"callback"		=> \&Zendure_connect_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Zendure_connect> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n".
		"## Body ##############\n".$json_body."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}

# Device List holen
sub Zendure_connect_getDeviceList{
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
		"callback"		=> \&Zendure_connect_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Zendure_connect> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n".
		"## Body ##############\n".$json_body."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}

# Antworten parsen und Devices anlegen
sub Zendure_connect_parseRequestAnswer {
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	my $responseData;

	if($err ne ""){
		Log3 $name, 1, $name.": <Zendure_connect> error while HTTP requesting ".$param->{url}." - $err"; 
		return Zendure_connect_retry($hash);
	}
	elsif($data ne ""){
		Log3 $name, 5, $name.": <Zendure_connect> parseRequestAnswer: URL:".$param->{url}." returned data:\n".
			"## HTTP-Statuscode ###\n".$param->{code} ."\n".
			"## Data ##############\n".$data."\n".
			"## Header ############\n".$param->{httpheader}."\n";
  
		# $param->{code} auswerten?
		unless (($param->{code} == 200) || ($param->{code} == 400)){
			Log3 $name, 1, $name.": <Zendure_connect> error while HTTP requesting ".$param->{url}." - code: ".$param->{code}; 
			return Zendure_connect_retry($hash);
		}

		# testen ob JSON OK ist
		if($data =~ m/\{.*\}/s){
			eval{
				$responseData = decode_json($data);
				Zendure_connect_convertBool($responseData);
			};
			if($@){
				my $error = $@;
				$error =~ m/^(.*?)\sat\s(.*?)$/;
				Log3 $name, 1, $name.": <Zendure_connect> error while HTTP requesting of command '".$param->{command}."' - Error while JSON decode: $1 ";
				Log3 $name, 5, $name.": <Zendure_connect> parseRequestAnswer: JSON decode at: $2";
				return Zendure_connect_retry($hash);
			}
			# testen ob Referenz vorhanden
			if(ref($responseData) ne 'HASH') {
				Log3 $name, 1, $name.": <Zendure_connect> error while HTTP requesting of command '".$param->{command}."' - Error, response isn't a reference!";
				return Zendure_connect_retry($hash);
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
			return Zendure_connect_retry($hash);
		}		                                                      

		if($param->{command} eq "getAccessToken") { 
			$hash->{helper}{auth} = $responseData;

			$hash->{helper}{accessToken} = $responseData->{data}{accessToken};
			$hash->{helper}{userId} = $responseData->{data}{userId};
			$hash->{helper}{iotUrl} = $responseData->{data}{iotUrl}.":1883";
	 		$hash->{helper}{iotUserName} = $responseData->{data}{iotUserName};
	 		$hash->{helper}{iotPassword} = decode_base64((($hash->{server} eq "v2") ? "b0sjUENneTZPWnhk" : "SDZzJGo5Q3ROYTBO"));
			readingsBeginUpdate($hash); 	
	 			readingsBulkUpdate($hash, "accessToken", $hash->{helper}{accessToken});
				readingsBulkUpdate($hash, "userId", $hash->{helper}{userId});
				readingsBulkUpdate($hash, "iotUrl", $hash->{helper}{iotUrl});
				readingsBulkUpdate($hash, "iotUserName", $hash->{helper}{iotUserName});
				readingsBulkUpdate($hash, "iotPassword", $hash->{helper}{iotPassword});
			readingsEndUpdate($hash, 1);
            
            Log3 $name, 3, $name.": <Zendure_connect> Access Token successful loaded!";

			# wenn OK, dann Liste holen
			Zendure_connect_getDeviceList($hash);
			
		}
		elsif($param->{command} eq "getDeviceList"){
			$hash->{helper}{devices} = $responseData;
		
			$hash->{devices} = scalar @{$responseData->{data}};
			
			push @{$hash->{helper}{subscriptions}}, "/server/app/".$hash->{helper}{userId}."/#";
			
			# MQTT_DEVICE Server anlegen
			Zendure_connect_configDevice($hash, $hash->{helper}{userId}, 1);

			my $k = 0;
			my $subscriptions = "";
			for my $i (0 .. ($hash->{devices}-1)){
				$subscriptions = "/".$responseData->{data}[$i]{productKey}."/".$responseData->{data}[$i]{deviceKey}."/# iot/".$responseData->{data}[$i]{productKey}."/".$responseData->{data}[$i]{deviceKey}."/#";
				push @{$hash->{helper}{subscriptions}}, $subscriptions;
				$k = $i + 1;
				readingsBeginUpdate($hash); 	
					readingsBulkUpdate($hash, "Device_".$k."_productKey", $responseData->{data}[$i]{productKey});
					readingsBulkUpdate($hash, "Device_".$k."_deviceKey", $responseData->{data}[$i]{deviceKey});
					readingsBulkUpdate($hash, "Device_".$k."_snNumber", $responseData->{data}[$i]{snNumber});
					readingsBulkUpdate($hash, "Device_".$k."_productName", $responseData->{data}[$i]{productName});
					readingsBulkUpdate($hash, "Device_".$k."_name", $responseData->{data}[$i]{name});
				readingsEndUpdate($hash, 1);
				
				# MQTT_DEVICE anlegen
				Zendure_connect_configDevice($hash, $i, 0);
			}
			Log3 $name, 3, $name.": <Zendure_connect> Device List successful loaded!";

			# MQTT_CLIENT modifizieren
			Zendure_connect_configClient($hash);
		}
		else{
			Log3 $name, 5, $name.": <Zendure_connect> parseRequestAnswer: unhandled command $param->{command}";
		}
		return undef;
	}
	Log3 $name, 1, $name.": <Zendure_connect> error while HTTP requesting URL:".$param->{url}." - no data!";
	return Zendure_connect_retry($hash);
}


# MQTT2_DEVICE anlegen
sub Zendure_connect_configDevice {
	my ($hash, $index, $isUserId) = @_;
	my $name = $hash->{NAME};

	my $snNumber;
	my $uniqueDeviceName;
	
	my $alias;
	my $productKey;
	my $deviceKey;
	
	my $readingList;
	my $setList;
	
	return unless($hash->{autocreate});
	
	if($isUserId){
		$snNumber = $index;
		$uniqueDeviceName = makeDeviceName($name."_".$snNumber);
		
		$alias = "Server $snNumber";
		$readingList = ".*/server/app/".$snNumber."/loginOut/force:.* force";
	}
	else{
		$snNumber = $hash->{helper}{devices}{data}[$index]{snNumber};
		$uniqueDeviceName = makeDeviceName($name."_".$snNumber);
		
		$alias = $hash->{helper}{devices}{data}[$index]{name};
		$productKey = $hash->{helper}{devices}{data}[$index]{productKey};
		$deviceKey = $hash->{helper}{devices}{data}[$index]{deviceKey};
		
		$readingList  = ".*/".$productKey."/".$deviceKey."/properties/report:.* { json2nameValue(\$EVENT, '', \$JSONMAP) }\n";
		$readingList .= ".*iot/".$productKey."/".$deviceKey."/properties/read:.* { json2nameValue(\$EVENT, 'iot_read_', \$JSONMAP) }\n";
		$readingList .= ".*iot/".$productKey."/".$deviceKey."/properties/write:.* { json2nameValue(\$EVENT, 'iot_write_', \$JSONMAP) }";

		$setList  = "Output:100,200,300,400,500,600 iot/".$productKey."/".$deviceKey.'/properties/write {"properties":{"outputLimit"'.":\$EVTPART1}} \n";
		$setList .= "Update:noArg iot/".$productKey."/".$deviceKey.'/properties/read {"properties":["getAll"]}'." \n";
		$setList .= "Bypass:0,1,2 iot/".$productKey."/".$deviceKey.'/properties/write {"properties":{"passMode"'.":\$EVTPART1}} \n";
		$setList .= "autoRecover:0,1 iot/".$productKey."/".$deviceKey.'/properties/write {"properties":{"autoRecover"'.":\$EVTPART1}}";

}


#				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/properties/report:.* { json2nameValue(\$EVENT, 'properties_report_', \$JSONMAP) }\n";
#				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/event/device:.* { json2nameValue(\$EVENT, 'event_device_', \$JSONMAP) }\n";
#				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/event/error:.* { json2nameValue(\$EVENT, 'event_error_', \$JSONMAP) }\n";
#				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/properties/read/reply:.* { json2nameValue(\$EVENT, 'properties_read_reply_', \$JSONMAP) }\n";
#				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/properties/write/reply:.* { json2nameValue(\$EVENT, 'properties_write_reply_', \$JSONMAP) }\n";
#				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/connected:.* { json2nameValue(\$EVENT, 'connected_', \$JSONMAP) }\n";
#				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/firmware/report:.* { json2nameValue(\$EVENT, 'firmware_report_', \$JSONMAP) }\n";
#				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/time-sync:.* { json2nameValue(\$EVENT, 'time-sync_', \$JSONMAP) }\n";
#				$text .= ".*iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/properties/read:.* { json2nameValue(\$EVENT, 'iot_properties_read_', \$JSONMAP) }\n";
#				$text .= ".*iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/properties/write:.* { json2nameValue(\$EVENT, 'iot_properties_write_', \$JSONMAP) }\n";
#				$text .= ".*iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/time-sync/reply:.* { json2nameValue(\$EVENT, 'iot_time-sync_reply_', \$JSONMAP) }\n";
#				$text .= "attr &lt\;name&gt\; setList &lt\;follow lines as example&gt\; \n";
#				$text .= "Output:100,200,300,400,500,600 iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/write {"properties":{"outputLimit"'.":\$EVTPART1}} \n";
#				$text .= "Update:noArg iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/read {"properties":["getAll"]}'." \n";
#				$text .= "Bypass:0,1,2 iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/write {"properties":{"passMode"'.":\$EVTPART1}} \n";
#				$text .= "autoRecover:0,1 iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/write {"properties":{"autoRecover"'.":\$EVTPART1}} \n";

	
	my $foundDevice = 0;
	my @devices = ();

	foreach my $fhem_dev (sort keys %main::defs) {
		push @devices, $main::defs{$fhem_dev} if($main::defs{$fhem_dev}{TYPE} eq 'MQTT2_DEVICE');
	}
	foreach my $device (@devices) {
		if($device->{DEF} eq $snNumber) {
			$foundDevice = 1;
			last;
		}
	}
	if(!$foundDevice) {
		# MQTT_DEVICE in Fhem anlegen
		my $ret = CommandDefMod(undef, "$uniqueDeviceName MQTT2_DEVICE $snNumber");
		
		if(defined($ret)){Log3 $name, 5, $name.": <Zendure_connect> addedDevice: CommandDefine with result: ".$ret};
		
		CommandAttr(undef,"$uniqueDeviceName alias $alias");
		CommandAttr(undef,"$uniqueDeviceName IODev $name");
		CommandAttr(undef,"$uniqueDeviceName readingList $readingList");
		CommandAttr(undef,"$uniqueDeviceName setList $setList") if(defined($setList));
		CommandAttr(undef,"$uniqueDeviceName stateFormat &nbsp");
		CommandAttr(undef,"$uniqueDeviceName autocreate no");
		
		CommandAttr(undef,"$uniqueDeviceName room $name");
		
		Log3 $name, 1, $name.": <Zendure_connect> Created device $uniqueDeviceName for $alias";
	}
}


# MQTT2_CLIENT modifizieren
sub Zendure_connect_configClient {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	$hash->{".usr"} = $hash->{helper}{iotUserName};
	$hash->{".pwd"} = $hash->{helper}{iotPassword};
	$hash->{DeviceName} = $hash->{helper}{iotUrl};
	$hash->{clientId} = $hash->{helper}{accessToken};
	
	#$hash->{devioLoglevel} = 4;
	
	CommandAttr(undef,"$name subscriptions ".join(" \n", @{$hash->{helper}{subscriptions}})) if(!defined(AttrVal($name, "subscriptions", undef)));
	CommandAttr(undef,"$name room $name") if(!defined(AttrVal($name, "room", undef)));
	CommandAttr(undef,"$name keepaliveTimeout 600") if(!defined(AttrVal($name, "keepaliveTimeout", undef)));
	CommandAttr(undef,"$name maxFailedConnects 5") if(!defined(AttrVal($name, "maxFailedConnects", undef)));
	CommandAttr(undef,"$name nextOpenDelay 10") if(!defined(AttrVal($name, "nextOpenDelay", undef)));
	CommandAttr(undef,"$name autocreate no") if(!defined(AttrVal($name, "autocreate", undef)));
	
	# reconnect nach Modifikation, Code 1:1 übernommen vom LandroidUtils.pm
	MQTT2_CLIENT_Disco($hash); # Make sure reconnect will work
	delete $readyfnlist{"$name.".$hash->{DeviceName}};
	delete $hash->{DevIoJustClosed};
	MQTT2_CLIENT_connect($hash, 1);
}

# Fehler beim Login, später nochmal probieren
sub Zendure_connect_retry {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	$hash->{nrFailedConnects}++;  # delete on CONNACK, zählt damit auch, wenn User Login fehlschlägt
	delete($hash->{inConnectFn});
	$readyfnlist{"$name.$hash->{DeviceName}"} = $hash;
}


# Convert Bool für JSON
sub Zendure_connect_convertBool {

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


1;
