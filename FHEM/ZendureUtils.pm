################################################################################
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
# attr updateInterval (minutes) For data that is not transmitted via MQTT
# 
# attr expert (0,1) Display of all data without selection by type
# 
# 
################################################################################

use HttpUtils;
use JSON;
use Data::Dumper;
use MIME::Base64;
use Storable qw( dclone );

use constant VERSION => "Zendure Connect v0.0.5";

use constant APPVERSION			=> "4.3.1";
use constant USERAGENT			=> "Zendure/4.3.1 (iPhone; iOS 14.4.2; Scale/3.00)";


my %server = (
	global => "v2",
	Global => "v2",
	v2 => "v2",
	eu => "eu",
	EU => "eu"
);

# Verbindung aufbauen ##########################################################
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
	
	$hash->{version} = VERSION;
	$hash->{server} = $server{$type};
	$hash->{autocreate} = $autocreate ? 1 : 0;
	
	Zendure_connect_getAccessToken($hash);
}

# Token holen ##################################################################
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
		"appVersion"		=> APPVERSION,
		"User-Agent"		=> USERAGENT,
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

# Device List holen ############################################################
sub Zendure_connect_getDeviceList{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $bladeAuth;
	
	if(defined($hash->{helper}{accessToken})){
		$bladeAuth = "bearer ".$hash->{helper}{accessToken};
	}
	else{
		Log3 $name, 1, $name.": no valid access token!";
		return undef;
	}
	
	my $url = "https://app.zendure.tech/".$hash->{server}."/productModule/device/queryDeviceListByConsumerId";

	my $body = {};

	# HTTP POST Anfrage senden
	my $json_body = encode_json($body);
	
	my $header    = {
		"Content-Type"		=> 'application/json',
		"Accept-Language"	=> 'de-DE',
		"appVersion"		=> APPVERSION,
		"User-Agent"		=> USERAGENT,
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

# Update Daten holen ###########################################################
sub Zendure_connect_getUpdate{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	if((ReadingsVal($name, "state", "") eq "opened") && (AttrVal($name,"updateInterval",0))){
		if(defined($hash->{helper}{devices}{data})){
			foreach my $devices(@{$hash->{helper}{devices}{data}}){
				# Abfrage mit Total 
				Zendure_connect_getEnergy($hash,$devices->{id},1);
				Zendure_connect_getElectric($hash,$devices->{id},1);
				# Abfrage Heute
				Zendure_connect_getEnergy($hash,$devices->{id});
				Zendure_connect_getElectric($hash,$devices->{id});
				Zendure_connect_getDetails($hash,$devices->{id});
			}
		}
		$hash->{helper}{updatetimer} = { hash=>$hash };
		InternalTimer(gettimeofday() + (AttrVal($name,"updateInterval",60) * 60), sub{ Zendure_connect_getUpdate($_[0]->{hash}) },$hash->{helper}{updatetimer});
		$hash->{polling} = "run";
	}
	else{
		$hash->{helper}{updatetimer} = { hash=>$hash };
		InternalTimer(gettimeofday() + 10, sub{ Zendure_connect_getUpdate($_[0]->{hash}) },$hash->{helper}{updatetimer});
		$hash->{polling} = "standby";
	}
	
	return undef;
}

# Detail Daten holen ###########################################################
sub Zendure_connect_getDetails{
	my ($hash, $id) = @_;
	my $name = $hash->{NAME};

	my $bladeAuth;

	if(defined($hash->{helper}{accessToken})){
		$bladeAuth = "bearer ".$hash->{helper}{accessToken};
	}
	else{
		readingsSingleUpdate($hash, 'state', 'No valid access token!', 1 );
		Log3 $name, 1, $name.": no valid access token!";
		return undef;
	}
	
	my $url = $hash->{helper}{serverNodeUrl}."/device/solarFlow/detail";
	
	# bekannte Links ###########################################################
	# https://app.zendure.tech/as/tdengine/device/solarFlow/electric 
	# https://app.zendure.tech/as/tdengine/device/solarFlow/energy
	# https://app.zendure.tech/as/platform/h5/time
	# https://app.zendure.tech/as/device/solarFlow/detail

	my $body = {
		"deviceId" => $id
	};

	# HTTP POST Anfrage senden
	my $json_body = encode_json($body);
	
	my $header    = {
		"Content-Type"		=> 'application/json',
		"Accept-Language"	=> 'de-DE',
		"appVersion"		=> APPVERSION,
		"User-Agent"		=> USERAGENT,
		"Accept"			=> '*/*',
		"Blade-Auth"		=> $bladeAuth
	};

	my $param = {
		"url"			=> $url,
		"method"		=> "POST",
		"timeout"		=> 10,
		"header"		=> $header, 
		"data"			=> $json_body, 
		"hash"			=> $hash,
		"command"		=> "getDetails",
		"id"			=> $id,
		"callback"		=> \&Zendure_connect_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Request> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n".
		"## Body ##############\n".$json_body."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}

# Energy Daten holen ###########################################################
sub Zendure_connect_getEnergy{
	my ($hash, $id, $period) = @_;
	my $name = $hash->{NAME};

	my $bladeAuth;
	
	$period = 0 if(!defined($period));

	if(defined($hash->{helper}{accessToken})){
		$bladeAuth = "bearer ".$hash->{helper}{accessToken};
	}
	else{
		Log3 $name, 1, $name.": no valid access token!";
		return undef;
	}
	
	my $url = $hash->{helper}{serverNodeUrl}."/tdengine/device/solarFlow/energy";

	# bekannte Links ###########################################################
	# https://app.zendure.tech/as/tdengine/device/solarFlow/electric 
	# https://app.zendure.tech/as/tdengine/device/solarFlow/energy
	# https://app.zendure.tech/as/platform/h5/time

	# nur Daten von heute
	my $today = sprintf( "%04d-%02d-%02d",((localtime)[5] +1900),((localtime)[4] +1),(localtime)[3]);
	my $type = 0;
	
	if($period == 1){
		# ganzer Zeitraum
		$today = "";
		$type = "";
	}
	
	my $body = {
		"aceId" => "",
		"deviceId" => $id, 
		"endDate" => $today,
		"zone" => "Europe\/Berlin",
		"type" => $type,
		"beginDate" => $today
	};

	# HTTP POST Anfrage senden
	my $json_body = encode_json($body);
	
	my $header    = {
		"Content-Type"		=> 'application/json',
		"Accept-Language"	=> 'de-DE',
		"appVersion"		=> APPVERSION,
		"User-Agent"		=> USERAGENT,
		"Accept"			=> '*/*',
		"Blade-Auth"		=> $bladeAuth
	};

	my $param = {
		"url"			=> $url,
		"method"		=> "POST",
		"timeout"		=> 10,
		"header"		=> $header, 
		"data"			=> $json_body, 
		"hash"			=> $hash,
		"command"		=> "getEnergy",
		"id"			=> $id,
		"period"		=> $period,
		"callback"		=> \&Zendure_connect_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Request> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n".
		"## Body ##############\n".$json_body."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}

# Electric Daten holen #########################################################
sub Zendure_connect_getElectric{
	my ($hash, $id, $period) = @_;
	my $name = $hash->{NAME};

	my $bladeAuth;

	$period = 0 if(!defined($period));

	if(defined($hash->{helper}{accessToken})){
		$bladeAuth = "bearer ".$hash->{helper}{accessToken};
	}
	else{
		Log3 $name, 1, $name.": no valid access token!";
		return undef;
	}
	
	my $url = $hash->{helper}{serverNodeUrl}."/tdengine/device/solarFlow/electric";
	
	# bekannte Links ###########################################################
	# https://app.zendure.tech/as/tdengine/device/solarFlow/electric 
	# https://app.zendure.tech/as/tdengine/device/solarFlow/energy
	# https://app.zendure.tech/as/platform/h5/time

	# nur Daten von heute
	my $today = sprintf( "%04d-%02d-%02d",((localtime)[5] +1900),((localtime)[4] +1),(localtime)[3]);
	my $type = 0;
	
	if($period == 1){
		# ganzer Zeitraum
		$today = "";
		$type = "";
	}

	my $body = {
		"aceId" => "",
		"deviceId" => $id,
		"endDate" => $today,
		"zone" => "Europe\/Berlin",
		"type" => $type,
		"beginDate" => $today
	};

	# HTTP POST Anfrage senden
	my $json_body = encode_json($body);
	
	my $header    = {
		"Content-Type"		=> 'application/json',
		"Accept-Language"	=> 'de-DE',
		"appVersion"		=> APPVERSION,
		"User-Agent"		=> USERAGENT,
		"Accept"			=> '*/*',
		"Blade-Auth"		=> $bladeAuth
	};

	my $param = {
		"url"			=> $url,
		"method"		=> "POST",
		"timeout"		=> 10,
		"header"		=> $header, 
		"data"			=> $json_body, 
		"hash"			=> $hash,
		"command"		=> "getElectric",
		"id"			=> $id,
		"period"		=> $period,
		"callback"		=> \&Zendure_connect_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Request> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n".
		"## Body ##############\n".$json_body."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}

# Antworten parsen und Devices anlegen #########################################
sub Zendure_connect_parseRequestAnswer {
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	my $responseData;
	my $hashMQTTDevice;

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
		unless ($param->{code} == 200){
			Log3 $name, 1, $name.": <Zendure_connect> error while HTTP requesting ".$param->{url}." returned data:\n".
			"## HTTP-Statuscode ###\n".$param->{code} ."\n".
			"## Data ##############\n".$data."\n".
			"## Header ############\n".$param->{httpheader}."\n";
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

		# bei code 200 kommt evtl. erweiterter Hinweise im JSON bei Error (z.B. wenn Token nicht mehr gültig)
		if ($param->{code} == 200){
			if($responseData->{code}){
				if(($responseData->{code} == 401) || ($responseData->{code} == 400)){
					Log3 $name, 1, $name.": <Zendure_connect> error while HTTP requesting ".$param->{url}." - code: ".$param->{code}." - msg: ".$responseData->{msg};
					return Zendure_connect_retry($hash);
 				}
			}
		}		                                                      

		if($param->{command} eq "getAccessToken") { 
			$hash->{helper}{auth} = $responseData;

			$hash->{serverNodeUrl} = $responseData->{data}{serverNodeUrl};

			$hash->{helper}{accessToken} = $responseData->{data}{accessToken};
			$hash->{helper}{userId} = $responseData->{data}{userId};
			$hash->{helper}{iotUrl} = $responseData->{data}{iotUrl}.":1883";
	 		$hash->{helper}{iotUserName} = $responseData->{data}{iotUserName};
	 		$hash->{helper}{iotPassword} = decode_base64((($hash->{server} eq "v2") ? "b0sjUENneTZPWnhk" : "SDZzJGo5Q3ROYTBO"));
	 		$hash->{helper}{serverNodeUrl} = $responseData->{data}{serverNodeUrl};
	 		$hash->{helper}{serverNode} = $responseData->{data}{serverNode};
	 		$hash->{helper}{zone} = $responseData->{data}{zone};

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

			my $subscriptions = "";
			foreach my $devices(@{$hash->{helper}{devices}{data}}){
				$subscriptions = "/".$devices->{productKey}."/".$devices->{deviceKey}."/# iot/".$devices->{productKey}."/".$devices->{deviceKey}."/#";
				push @{$hash->{helper}{subscriptions}}, $subscriptions;
				readingsBeginUpdate($hash); 	
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_productKey", $devices->{productKey});
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_deviceKey", $devices->{deviceKey});
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_snNumber", $devices->{snNumber});
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_productName", $devices->{productName});
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_name", $devices->{name});
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_id", $devices->{id});
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_productType", $devices->{productType});
				readingsEndUpdate($hash, 1);
				
				# MQTT_DEVICE anlegen
				Zendure_connect_configDevice($hash, $devices, 0);
			}
			Log3 $name, 3, $name.": <Zendure_connect> Device List successful loaded!";

			# MQTT_CLIENT modifizieren
			Zendure_connect_configClient($hash);
			
			# wenn OK dann Daten holen vorher Timer zurücksetzen
			if($hash->{helper}{updatetimer}) {
				RemoveInternalTimer($hash->{helper}{updatetimer});
				delete($hash->{helper}{updatetimer});
			}
			# Daten holen
			Zendure_connect_getUpdate($hash);
			
		}
		elsif($param->{command} eq "getElectric"){
			foreach my $devices(@{$hash->{helper}{devices}{data}}){
				if($devices->{id} eq $param->{id}){
					# merge der Hashes damit {total} & {today} erhalten bleiben
					@{$devices->{electric}}{ keys %$responseData } = values %$responseData;

					delete($devices->{electric}{data}{energyVos}); 	#Diagrammdaten gelöscht
					delete($devices->{electric}{data}{data}); 		#Diagrammdaten gelöscht

					if($param->{period} == 1){
						$devices->{electric}{total} = dclone($devices->{electric}{data});
					}
					else{
						$devices->{electric}{today} = dclone($devices->{electric}{data});
					}

			# productType = 8 	=> HUB 2000
			# productType = 17 	=> Hyper 2000

					$hashMQTTDevice = Zendure_connect_getHashByDEF($hash, $devices->{snNumber});

					if((($devices->{productType} != 8) && ($devices->{productType} != 17)) || (AttrVal($name,"expert",0))){
						readingsBeginUpdate($hashMQTTDevice); 	
							readingsBulkUpdate($hashMQTTDevice, "electric_today_toHome", $devices->{electric}{today}{toHome});
							readingsBulkUpdate($hashMQTTDevice, "electric_today_bindDeviceInput", $devices->{electric}{today}{bindDeviceInput});
							readingsBulkUpdate($hashMQTTDevice, "electric_today_fromSolar", $devices->{electric}{today}{fromSolar});
							readingsBulkUpdate($hashMQTTDevice, "electric_today_outputToBindDevice", $devices->{electric}{today}{outputToBindDevice});

							readingsBulkUpdate($hashMQTTDevice, "electric_total_toHome", $devices->{electric}{total}{toHome});
							readingsBulkUpdate($hashMQTTDevice, "electric_total_bindDeviceInput", $devices->{electric}{total}{bindDeviceInput});
							readingsBulkUpdate($hashMQTTDevice, "electric_total_fromSolar", $devices->{electric}{total}{fromSolar});
							readingsBulkUpdate($hashMQTTDevice, "electric_total_outputToBindDevice", $devices->{electric}{total}{outputToBindDevice});
						readingsEndUpdate($hashMQTTDevice, 1);
					}
					elsif(($devices->{productType} == 8) || ($devices->{productType} == 17)){
						# keine relevanten Daten vorhanden
					}
				}
			}
			Log3 $name, 5, $name.": <Zendure_connect> Electric data successful loaded!";
		}
		elsif($param->{command} eq "getEnergy"){
			foreach my $devices(@{$hash->{helper}{devices}{data}}){
				if($devices->{id} eq $param->{id}){
					# merge der Hashes damit {total} & {today} erhalten bleiben
					@{$devices->{energy}}{ keys %$responseData } = values %$responseData;
					
					delete($devices->{energy}{data}{energyVos}); 	#Diagrammdaten gelöscht
					delete($devices->{energy}{data}{data}); 		#Diagrammdaten gelöscht

					if($param->{period} == 1){
						$devices->{energy}{total} = dclone($devices->{energy}{data});
					}
					else{
						$devices->{energy}{today} = dclone($devices->{energy}{data});
					}

			# productType = 8 	=> HUB 2000
			# productType = 17 	=> Hyper 2000

					$hashMQTTDevice = Zendure_connect_getHashByDEF($hash, $devices->{snNumber});

					if((($devices->{productType} != 8) && ($devices->{productType} != 17)) || (AttrVal($name,"expert",0))){
						readingsBeginUpdate($hashMQTTDevice); 	
							readingsBulkUpdate($hashMQTTDevice, "energy_today_batteryOutput", $devices->{energy}{today}{batteryOutput});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_batteryInput", $devices->{energy}{today}{batteryInput});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_solar", $devices->{energy}{today}{solar});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_outputToBindDevice", $devices->{energy}{today}{outputToBindDevice});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_bindDeviceInput", $devices->{energy}{today}{bindDeviceInput});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_home", $devices->{energy}{today}{home});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_outputToInverse", $devices->{energy}{today}{outputToInverse});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_gridInputTotal", $devices->{energy}{today}{gridInputTotal});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_socketOutputTotal", $devices->{energy}{today}{socketOutputTotal});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_dcOutputTotal", $devices->{energy}{today}{dcOutputTotal});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_gridDirectTotal", $devices->{energy}{today}{gridDirectTotal});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_acOutputTotal", $devices->{energy}{today}{acOutputTotal});

							readingsBulkUpdate($hashMQTTDevice, "energy_total_batteryOutput", $devices->{energy}{total}{batteryOutput});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_batteryInput", $devices->{energy}{total}{batteryInput});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_solar", $devices->{energy}{total}{solar});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_outputToBindDevice", $devices->{energy}{total}{outputToBindDevice});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_bindDeviceInput", $devices->{energy}{total}{bindDeviceInput});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_home", $devices->{energy}{total}{home});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_outputToInverse", $devices->{energy}{total}{outputToInverse});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_gridInputTotal", $devices->{energy}{total}{gridInputTotal});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_socketOutputTotal", $devices->{energy}{total}{socketOutputTotal});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_dcOutputTotal", $devices->{energy}{total}{dcOutputTotal});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_gridDirectTotal", $devices->{energy}{total}{gridDirectTotal});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_acOutputTotal", $devices->{energy}{total}{acOutputTotal});
						readingsEndUpdate($hashMQTTDevice, 1);
					}
					elsif($devices->{productType} == 8){
						readingsBeginUpdate($hashMQTTDevice); 	
							readingsBulkUpdate($hashMQTTDevice, "energy_today_batteryOutput", $devices->{energy}{today}{batteryOutput});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_batteryInput", $devices->{energy}{today}{batteryInput});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_solar", $devices->{energy}{today}{solar});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_home", $devices->{energy}{today}{home});

							readingsBulkUpdate($hashMQTTDevice, "energy_total_batteryOutput", $devices->{energy}{total}{batteryOutput});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_batteryInput", $devices->{energy}{total}{batteryInput});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_solar", $devices->{energy}{total}{solar});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_home", $devices->{energy}{total}{home});
						readingsEndUpdate($hashMQTTDevice, 1);
					}
					elsif($devices->{productType} == 17){
						readingsBeginUpdate($hashMQTTDevice); 	
							readingsBulkUpdate($hashMQTTDevice, "energy_today_batteryOutput", $devices->{energy}{today}{batteryOutput});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_batteryInput", $devices->{energy}{today}{batteryInput});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_solar", $devices->{energy}{today}{solar});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_home", $devices->{energy}{today}{home});
							readingsBulkUpdate($hashMQTTDevice, "energy_today_gridInputTotal", $devices->{energy}{today}{gridInputTotal});

							readingsBulkUpdate($hashMQTTDevice, "energy_total_batteryOutput", $devices->{energy}{total}{batteryOutput});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_batteryInput", $devices->{energy}{total}{batteryInput});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_solar", $devices->{energy}{total}{solar});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_home", $devices->{energy}{total}{home});
							readingsBulkUpdate($hashMQTTDevice, "energy_total_gridInputTotal", $devices->{energy}{total}{gridInputTotal});
						readingsEndUpdate($hashMQTTDevice, 1);
					}
				}
			}
			Log3 $name, 5, $name.": <Zendure_connect> Energy data successful loaded!";
		}
		elsif($param->{command} eq "getDetails"){
			foreach my $devices(@{$hash->{helper}{devices}{data}}){
				if($devices->{id} eq $param->{id}){
					# merge der Hashes damit {total} & {today} erhalten bleiben
					#@{$devices->{detail}}{ keys %$responseData } = values %$responseData;
					$devices->{detail} = $responseData;

					$hashMQTTDevice = Zendure_connect_getHashByDEF($hash, $devices->{snNumber});
					
					readingsBeginUpdate($hashMQTTDevice); 	
						readingsBulkUpdate($hashMQTTDevice, "createTime", $devices->{detail}{data}{createTime});
						readingsBulkUpdate($hashMQTTDevice, "updateTime", $devices->{detail}{data}{updateTime});
					readingsEndUpdate($hashMQTTDevice, 1);
					
					foreach my $pack(@{$devices->{detail}{data}{packDataList}}){
						readingsBeginUpdate($hashMQTTDevice); 	
							readingsBulkUpdate($hashMQTTDevice, "packData_".$pack->{sn}."_createTime", $pack->{createTime});
							readingsBulkUpdate($hashMQTTDevice, "packData_".$pack->{sn}."_packType", $pack->{packType});
						readingsEndUpdate($hash, 1);
					}
				}
			}
			Log3 $name, 5, $name.": <Zendure_connect> Detail data successful loaded!";
		}
		else{
			Log3 $name, 5, $name.": <Zendure_connect> parseRequestAnswer: unhandled command $param->{command}";
		}
		return undef;
	}
	Log3 $name, 1, $name.": <Zendure_connect> error while HTTP requesting URL:".$param->{url}." - no data!";
	return Zendure_connect_retry($hash);
}

# MQTT2_DEVICE anlegen #########################################################
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
	my $jsonMap;
	
	return unless($hash->{autocreate});
	
	if($isUserId){
		$snNumber = $index;
		$uniqueDeviceName = makeDeviceName($name."_".$snNumber);
		
		$alias = "Server $snNumber";
		$readingList = ".*/server/app/".$snNumber."/loginOut/force:.* force";
	}
	else{
		$snNumber = $index->{snNumber};
		$uniqueDeviceName = makeDeviceName($name."_".$snNumber);
		
		$alias = $index->{name};
		$productKey = $index->{productKey};
		$deviceKey = $index->{deviceKey};
		
		$readingList  = ".*/".$productKey."/".$deviceKey."/properties/report:.* { json2nameValue(\$EVENT, '', \$JSONMAP, undef, 'packData') }\n";
		$readingList .= ".*/".$productKey."/".$deviceKey."/properties/report:.* { hashKeyRename(json2nameValue(\$EVENT,undef,undef,'packData'),'packData_(.*)_sn:(.*)','(\\d+)') }\n";
		$readingList .= ".*iot/".$productKey."/".$deviceKey."/properties/read:.* { json2nameValue(\$EVENT, 'iot_read_', \$JSONMAP) }\n";
		$readingList .= ".*iot/".$productKey."/".$deviceKey."/properties/write:.* { json2nameValue(\$EVENT, 'iot_write_', \$JSONMAP) }";

		$setList  = "Output:30,60,90,100,200,300,400,500,600,700,800 iot/".$productKey."/".$deviceKey.'/properties/write {"properties":{"outputLimit"'.":\$EVTPART1}} \n";
		$setList .= "Update:noArg iot/".$productKey."/".$deviceKey.'/properties/read {"properties":["getAll"]}'." \n";
		$setList .= "Bypass:0,1,2 iot/".$productKey."/".$deviceKey.'/properties/write {"properties":{"passMode"'.":\$EVTPART1}} \n";
		$setList .= "autoRecover:0,1 iot/".$productKey."/".$deviceKey.'/properties/write {"properties":{"autoRecover"'.":\$EVTPART1}} \n";
		$setList .= "Buzzer:0,1 iot/".$productKey."/".$deviceKey.'/properties/write {"properties":{"buzzerSwitch"'.":\$EVTPART1}} \n";
		$setList .= "minSoc:100,200,300,400,500 iot/".$productKey."/".$deviceKey.'/properties/write {"properties":{"minSoc"'.":\$EVTPART1}}";
		
		$jsonMap  = "properties_acMode:acMode\n";
		$jsonMap .= "properties_autoModel:autoModel\n";
		$jsonMap .= "properties_autoRecover:autoRecover\n";
		$jsonMap .= "properties_blueOta:blueOta\n";
		$jsonMap .= "properties_buzzerSwitch:buzzerSwitch\n";
		$jsonMap .= "properties_electricLevel:electricLevel\n";
		$jsonMap .= "properties_gridPower:gridPower\n";
		$jsonMap .= "properties_heatState:heatState\n";
		$jsonMap .= "properties_hubState:hubState\n";
		$jsonMap .= "properties_inputLimit:inputLimit\n";
		$jsonMap .= "properties_inputMode:inputMode\n";
		$jsonMap .= "properties_inverseMaxPower:inverseMaxPower\n";
		$jsonMap .= "properties_masterSoftVersion:masterSoftVersion\n";
		$jsonMap .= "properties_masterSwitch:masterSwitch\n";
		$jsonMap .= "properties_masterhaerVersion:masterhaerVersion\n";
		$jsonMap .= "properties_minSoc:minSoc\n";
		$jsonMap .= "properties_outputHomePower:outputHomePower\n";
		$jsonMap .= "properties_outputHomePowerCycle:outputHomePowerCycle\n";
		$jsonMap .= "properties_outputLimit:outputLimit\n";
		$jsonMap .= "properties_outputPackPower:outputPackPower\n";
		$jsonMap .= "properties_outputPackPowerCycle:outputPackPowerCycle\n";
		$jsonMap .= "properties_packInputPower:packInputPower\n";
		$jsonMap .= "properties_packInputPowerCycle:packInputPowerCycle\n";
		$jsonMap .= "properties_packNum:packNum\n";
		$jsonMap .= "properties_packState:packState\n";
		$jsonMap .= "properties_pass:pass\n";
		$jsonMap .= "properties_passMode:passMode\n";
		$jsonMap .= "properties_pvBrand:pvBrand\n";
		$jsonMap .= "properties_remainInputTime:remainInputTime\n";
		$jsonMap .= "properties_remainOutTime:remainOutTime\n";
		$jsonMap .= "properties_smartMode:smartMode\n";
		$jsonMap .= "properties_smartPower:smartPower\n";
		$jsonMap .= "properties_socSet:socSet\n";
		$jsonMap .= "properties_solarInputPower:solarInputPower\n";
		$jsonMap .= "properties_solarPower1:solarPower1\n";
		$jsonMap .= "properties_solarPower1Cycle:solarPower1Cycle\n";
		$jsonMap .= "properties_solarPower2:solarPower2\n";
		$jsonMap .= "properties_solarPower2Cycle:solarPower2Cycle\n";
		$jsonMap .= "properties_wifiState:wifiState";
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
		CommandAttr(undef,"$uniqueDeviceName jsonMap $jsonMap") if(defined($jsonMap));
		CommandAttr(undef,"$uniqueDeviceName readingList $readingList");
		CommandAttr(undef,"$uniqueDeviceName setList $setList") if(defined($setList));
		CommandAttr(undef,"$uniqueDeviceName stateFormat &nbsp");
		CommandAttr(undef,"$uniqueDeviceName autocreate no");
		
		CommandAttr(undef,"$uniqueDeviceName room $name");
		
		Log3 $name, 1, $name.": <Zendure_connect> Created device $uniqueDeviceName for $alias";
	}
}

# MQTT2_CLIENT modifizieren ####################################################
sub Zendure_connect_configClient {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	$hash->{".usr"} = $hash->{helper}{iotUserName};
	$hash->{".pwd"} = $hash->{helper}{iotPassword};
	$hash->{DeviceName} = $hash->{helper}{iotUrl};
	$hash->{clientId} = $hash->{helper}{accessToken};
	
	addToDevAttrList($name,"updateInterval expert:0,1");
	
	CommandAttr(undef,"$name subscriptions ".join(" \n", @{$hash->{helper}{subscriptions}})) if(!defined(AttrVal($name, "subscriptions", undef)));
	CommandAttr(undef,"$name room $name") if(!defined(AttrVal($name, "room", undef)));
	CommandAttr(undef,"$name keepaliveTimeout 600") if(!defined(AttrVal($name, "keepaliveTimeout", undef)));
	CommandAttr(undef,"$name maxFailedConnects 5") if(!defined(AttrVal($name, "maxFailedConnects", undef)));
	CommandAttr(undef,"$name nextOpenDelay 10") if(!defined(AttrVal($name, "nextOpenDelay", undef)));
	CommandAttr(undef,"$name autocreate no") if(!defined(AttrVal($name, "autocreate", undef)));
	#CommandAttr(undef,"$name updateInterval 20") if(!defined(AttrVal($name, "updateInterval", undef)));
	
	# reconnect nach Modifikation, Code 1:1 übernommen vom LandroidUtils.pm
	MQTT2_CLIENT_Disco($hash); # Make sure reconnect will work
	delete $readyfnlist{"$name.".$hash->{DeviceName}};
	delete $hash->{DevIoJustClosed};
	MQTT2_CLIENT_connect($hash, 1);
}

# Fehler beim Login, später nochmal probieren ##################################
sub Zendure_connect_retry {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	$hash->{nrFailedConnects}++;  # delete on CONNACK, zählt damit auch, wenn User Login fehlschlägt
	delete($hash->{inConnectFn});
	$readyfnlist{"$name.$hash->{DeviceName}"} = $hash;
}

# Hash von MQTT2 Device holen ##################################################
sub Zendure_connect_getHashByDEF {
  	my ($hash, $def) = @_;
  	my $name = $hash->{NAME};

  	foreach my $fhem_dev (sort keys %main::defs) {
    	return $main::defs{$fhem_dev} if($main::defs{$fhem_dev}{TYPE} eq 'MQTT2_DEVICE' && $main::defs{$fhem_dev}{DEF} eq $def);
  	}
		
  	return undef;
}

# Convert Bool #################################################################
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
