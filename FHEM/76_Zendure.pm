# FHEM Modul für Zendure Login Daten 
package main;

use strict;
use warnings;

use HttpUtils;
use JSON;
use Data::Dumper;
use MIME::Base64;
use Storable qw( dclone );

use constant VERSION 			=> "v0.0.5";

use constant APPVERSION			=> "4.3.1";
use constant USERAGENT			=> "Zendure/4.3.1 (iPhone; iOS 14.4.2; Scale/3.00)";


my %server = (
	global => "v2",
	Global => "v2",
	v2 => "v2",
	eu => "eu",
	EU => "eu"
);

# Init #########################################################################
sub Zendure_Initialize($) {
	my ($hash) = @_;

	# Definieren von FHEM-Funktionen
	$hash->{DefFn}		= "Zendure_Define";
	$hash->{SetFn}		= "Zendure_Set";
	$hash->{GetFn}		= "Zendure_Get";
	$hash->{AttrFn}		= "Zendure_Attr";
	$hash->{AttrList}	= "updateInterval expert:0,1 ".$readingFnAttributes;}

# Definition des Geräts in FHEM ################################################
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

# Set ##########################################################################
sub Zendure_Set($$@) {
	my ($hash, $name, $cmd, @args) = @_;

	my $list = "Login:noArg Update:noArg";

	if ($cmd eq "Login") {
		readingsSingleUpdate($hash, 'state', $cmd, 1 );
		Zendure_getAccessToken($hash);
		return undef;
	}
	elsif ($cmd eq "Update") {
		readingsSingleUpdate($hash, 'state', $cmd, 1 );
		Zendure_getDeviceList($hash);
		return undef;
	}

	return "Unknown argument $cmd, choose one of $list";
}

# Token holen ##################################################################
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
		"callback"		=> \&Zendure_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Request> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n".
		"## Body ##############\n".$json_body."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}

# Device List holen ############################################################
sub Zendure_getDeviceList{
	my ($hash) = @_;
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
		"callback"		=> \&Zendure_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Request> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n".
		"## Body ##############\n".$json_body."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}

# Update Daten holen ###########################################################
sub Zendure_getUpdate{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	if(defined($hash->{helper}{devices}{data})){
		foreach my $devices(@{$hash->{helper}{devices}{data}}){
			# Abfrage mit Total 
			Zendure_getEnergy($hash,$devices->{id},1);
			Zendure_getElectric($hash,$devices->{id},1);
			# Abfrage Heute
			Zendure_getEnergy($hash,$devices->{id});
			Zendure_getElectric($hash,$devices->{id});
			Zendure_getDetails($hash,$devices->{id});
		}
	}
	
	InternalTimer(gettimeofday() + (AttrVal($name,"updateInterval",60) * 60), "Zendure_getUpdate", $hash) if(AttrVal($name,"updateInterval",0));	
	
	return undef;
}

# Detail Daten holen ###########################################################
sub Zendure_getDetails{
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
		"callback"		=> \&Zendure_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Request> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n".
		"## Body ##############\n".$json_body."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}

# Energy Daten holen ###########################################################
sub Zendure_getEnergy{
	my ($hash, $id, $period) = @_;
	my $name = $hash->{NAME};

	my $bladeAuth;
	
	$period = 0 if(!defined($period));

	if(defined($hash->{helper}{accessToken})){
		$bladeAuth = "bearer ".$hash->{helper}{accessToken};
	}
	else{
		readingsSingleUpdate($hash, 'state', 'No valid access token!', 1 );
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
	
	# type mögliche Werte "",0,1,2,3,4
	# "" ganzer Zeitrauf seit IBN
	# 0 = Tag
	# 1 = Woche				?
	# 2 = Monat				?
	# 3 = Jahr				?
	# 4 = Benutzerdefiniert	?
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
		"callback"		=> \&Zendure_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Request> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n".
		"## Body ##############\n".$json_body."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}

# Electric Daten holen #########################################################
sub Zendure_getElectric{
	my ($hash, $id, $period) = @_;
	my $name = $hash->{NAME};

	my $bladeAuth;

	$period = 0 if(!defined($period));

	if(defined($hash->{helper}{accessToken})){
		$bladeAuth = "bearer ".$hash->{helper}{accessToken};
	}
	else{
		readingsSingleUpdate($hash, 'state', 'No valid access token!', 1 );
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
		"callback"		=> \&Zendure_parseRequestAnswer,
		"loglevel"		=> AttrVal($name, "verbose", 4)
	};

	Log3 $name, 5, $name.": <Request> URL:".$url." send:\n".
		"## Header ############\n".Dumper($param->{header})."\n".
		"## Body ##############\n".$json_body."\n";

	HttpUtils_NonblockingGet( $param );

	return undef;
}

# Antworten parsen und Readings anlegen ########################################
sub Zendure_parseRequestAnswer {
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};

	my $responseData;

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
		unless ($param->{code} == 200){
			Log3 $name, 1, $name.": error while HTTP requesting ".$param->{url}." returned data:\n".
			"## HTTP-Statuscode ###\n".$param->{code} ."\n".
			"## Data ##############\n".$data."\n".
			"## Header ############\n".$param->{httpheader}."\n";
 
			readingsSingleUpdate($hash, 'state', 'error - code '.$param->{code}, 1 );
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

		# bei code 200 kommt evtl. erweiterter Hinweise im JSON bei Error (z.B. wenn Token nicht mehr gültig)
		if ($param->{code} == 200){
			if($responseData->{code}){
				if(($responseData->{code} == 401) || ($responseData->{code} == 400)){
					Log3 $name, 1, $name.": error while HTTP requesting ".$param->{url}." - code: ".$param->{code}." - msg: ".$responseData->{msg};
					readingsSingleUpdate($hash, 'state', 'error - '.$responseData->{msg}, 1 );
					return undef;
 				}
			}
		}

		if($param->{command} eq "getAccessToken") { 
			$hash->{helper}{auth} = $responseData;
			
			# für GET showData
			$hash->{helper}{get}{auth} = dclone($responseData);
			
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

			# für GET showData
			$hash->{helper}{get}{devices} = dclone($responseData);
		
			$hash->{devices} = scalar @{$responseData->{data}};
			
			# nur für ConfigProposal ersten Eintrag nehmen
			$hash->{helper}{productKey} = $responseData->{data}[0]{productKey};
			$hash->{helper}{deviceKey} = $responseData->{data}[0]{deviceKey};
			$hash->{helper}{id} = $responseData->{data}[0]{id};
			
			$hash->{helper}{subscriptions} = "/".$responseData->{data}[0]{productKey}."/".$responseData->{data}[0]{deviceKey}."/# iot/".$responseData->{data}[0]{productKey}."/".$responseData->{data}[0]{deviceKey}."/# \n";
			####
			
			my $subscriptions = "";
			foreach my $devices(@{$hash->{helper}{devices}{data}}){
				$subscriptions = "/".$devices->{productKey}."/".$devices->{deviceKey}."/# iot/".$devices->{productKey}."/".$devices->{deviceKey}."/#";
				readingsBeginUpdate($hash); 	
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_productKey", $devices->{productKey});
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_deviceKey", $devices->{deviceKey});
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_snNumber", $devices->{snNumber});
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_productName", $devices->{productName});
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_name", $devices->{name});
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_id", $devices->{id});
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_productType", $devices->{productType});
					readingsBulkUpdate($hash, "Device_".$devices->{id}."_subscriptions", $subscriptions);
				readingsEndUpdate($hash, 1);
			}
			
			readingsSingleUpdate($hash, 'state', 'Device List successful loaded!', 1 );
			
			# wenn OK dann Daten holen
			Zendure_getUpdate($hash);
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

					if((($devices->{productType} != 8) && ($devices->{productType} != 17)) || (AttrVal($name,"expert",0))){
						readingsBeginUpdate($hash); 	
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_electric_today_toHome", $devices->{electric}{today}{toHome});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_electric_today_bindDeviceInput", $devices->{electric}{today}{bindDeviceInput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_electric_today_fromSolar", $devices->{electric}{today}{fromSolar});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_electric_today_outputToBindDevice", $devices->{electric}{today}{outputToBindDevice});

							readingsBulkUpdate($hash, "Device_".$devices->{id}."_electric_total_toHome", $devices->{electric}{total}{toHome});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_electric_total_bindDeviceInput", $devices->{electric}{total}{bindDeviceInput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_electric_total_fromSolar", $devices->{electric}{total}{fromSolar});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_electric_total_outputToBindDevice", $devices->{electric}{total}{outputToBindDevice});
						readingsEndUpdate($hash, 1);
					}
					elsif(($devices->{productType} == 8) || ($devices->{productType} == 17)){
						# keine relevanten Daten vorhanden
					}
				}
			}
			readingsSingleUpdate($hash, 'state', 'Electric data successful loaded!', 1 );
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

					if((($devices->{productType} != 8) && ($devices->{productType} != 17)) || (AttrVal($name,"expert",0))){
						readingsBeginUpdate($hash); 	
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_batteryOutput", $devices->{energy}{today}{batteryOutput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_batteryInput", $devices->{energy}{today}{batteryInput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_solar", $devices->{energy}{today}{solar});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_outputToBindDevice", $devices->{energy}{today}{outputToBindDevice});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_bindDeviceInput", $devices->{energy}{today}{bindDeviceInput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_home", $devices->{energy}{today}{home});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_outputToInverse", $devices->{energy}{today}{outputToInverse});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_gridInputTotal", $devices->{energy}{today}{gridInputTotal});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_socketOutputTotal", $devices->{energy}{today}{socketOutputTotal});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_dcOutputTotal", $devices->{energy}{today}{dcOutputTotal});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_gridDirectTotal", $devices->{energy}{today}{gridDirectTotal});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_acOutputTotal", $devices->{energy}{today}{acOutputTotal});

							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_batteryOutput", $devices->{energy}{total}{batteryOutput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_batteryInput", $devices->{energy}{total}{batteryInput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_solar", $devices->{energy}{total}{solar});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_outputToBindDevice", $devices->{energy}{total}{outputToBindDevice});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_bindDeviceInput", $devices->{energy}{total}{bindDeviceInput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_home", $devices->{energy}{total}{home});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_outputToInverse", $devices->{energy}{total}{outputToInverse});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_gridInputTotal", $devices->{energy}{total}{gridInputTotal});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_socketOutputTotal", $devices->{energy}{total}{socketOutputTotal});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_dcOutputTotal", $devices->{energy}{total}{dcOutputTotal});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_gridDirectTotal", $devices->{energy}{total}{gridDirectTotal});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_acOutputTotal", $devices->{energy}{total}{acOutputTotal});
						readingsEndUpdate($hash, 1);
					}
					elsif($devices->{productType} == 8){
						readingsBeginUpdate($hash); 	
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_batteryOutput", $devices->{energy}{today}{batteryOutput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_batteryInput", $devices->{energy}{today}{batteryInput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_solar", $devices->{energy}{today}{solar});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_home", $devices->{energy}{today}{home});

							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_batteryOutput", $devices->{energy}{total}{batteryOutput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_batteryInput", $devices->{energy}{total}{batteryInput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_solar", $devices->{energy}{total}{solar});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_home", $devices->{energy}{total}{home});
						readingsEndUpdate($hash, 1);
					}
					elsif($devices->{productType} == 17){
						readingsBeginUpdate($hash); 	
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_batteryOutput", $devices->{energy}{today}{batteryOutput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_batteryInput", $devices->{energy}{today}{batteryInput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_solar", $devices->{energy}{today}{solar});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_home", $devices->{energy}{today}{home});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_today_gridInputTotal", $devices->{energy}{today}{gridInputTotal});

							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_batteryOutput", $devices->{energy}{total}{batteryOutput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_batteryInput", $devices->{energy}{total}{batteryInput});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_solar", $devices->{energy}{total}{solar});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_home", $devices->{energy}{total}{home});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_energy_total_gridInputTotal", $devices->{energy}{total}{gridInputTotal});
						readingsEndUpdate($hash, 1);
					}
				}
			}
			readingsSingleUpdate($hash, 'state', 'Energy data successful loaded!', 1 );
		}
		elsif($param->{command} eq "getDetails"){
			foreach my $devices(@{$hash->{helper}{devices}{data}}){
				if($devices->{id} eq $param->{id}){
					# merge der Hashes damit {total} & {today} erhalten bleiben
					#@{$devices->{detail}}{ keys %$responseData } = values %$responseData;
					$devices->{detail} = $responseData;
					
					readingsBeginUpdate($hash); 	
						readingsBulkUpdate($hash, "Device_".$devices->{id}."_createTime", $devices->{detail}{data}{createTime});
						readingsBulkUpdate($hash, "Device_".$devices->{id}."_updateTime", $devices->{detail}{data}{updateTime});
					readingsEndUpdate($hash, 1);
					
					foreach my $pack(@{$devices->{detail}{data}{packDataList}}){
						readingsBeginUpdate($hash); 	
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_pack_".$pack->{id}."_createTime", $pack->{createTime});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_pack_".$pack->{id}."_packType", $pack->{packType});
							readingsBulkUpdate($hash, "Device_".$devices->{id}."_pack_".$pack->{id}."_snNumber", $pack->{sn});
						readingsEndUpdate($hash, 1);
					}
				}
			}
			readingsSingleUpdate($hash, 'state', 'Detail data successful loaded!', 1 );
		}
		else{
			Log3 $name, 5, $name.": <parseRequestAnswer> unhandled command $param->{command}";
		}
		return undef;
	}
	Log3 $name, 1, $name.": error while HTTP requesting URL:".$param->{url}." - no data!";
	return undef;
}

# Get ##########################################################################
sub Zendure_Get {
	my ($hash, $name, $opt, @args) = @_;

	return "\"get $name\" needs at least one argument" unless(defined($opt));

	Log3 $name, 5, $name.": <Get> called for $name : msg = $opt";

	my $dump;
	my $dumpList;
	
	my $usage = "Unknown argument $opt, choose one of showData:AccessToken,DeviceList,Energy,Electric,Details ConfigProposal:noArg Account:noArg";
	
	if($opt eq "showData"){
		if ($args[0] eq "AccessToken"){
			if(defined($hash->{helper}{get}{auth})){
		        if(%{$hash->{helper}{get}{auth}}){
		        	Zendure_convertBool($hash->{helper}{get}{auth});
				    local $Data::Dumper::Deepcopy = 1;
					$dump = Dumper($hash->{helper}{get}{auth});
					$dump =~ s{\A\$VAR\d+\s*=\s*}{};
		        	return "stored data:\n".$dump;
		        }
		    }
			return "No data available: $opt $args[0]";	
		} 
		elsif($args[0] eq "DeviceList"){
			if(defined($hash->{helper}{get}{devices})){
				if(%{$hash->{helper}{get}{devices}}){
					Zendure_convertBool($hash->{helper}{get}{devices});
					local $Data::Dumper::Deepcopy = 1;
					$dump = Dumper($hash->{helper}{get}{devices});
					$dump =~ s{\A\$VAR\d+\s*=\s*}{};
					return "stored data:\n".$dump;
				}
			}
			return "No data available: $opt $args[0]";
		}
		elsif($args[0] eq "Electric"){
			if(defined($hash->{helper}{devices}{data})){
				$dumpList = "";
				foreach my $devices(@{$hash->{helper}{devices}{data}}){
					$dumpList .= "DeviceId: ".$devices->{id}."\n";
					if(defined($devices->{electric})){
						Zendure_convertBool($devices->{electric});
						local $Data::Dumper::Deepcopy = 1;
						$dump = Dumper($devices->{electric});
						$dump =~ s{\A\$VAR\d+\s*=\s*}{};
					}
					$dumpList .= $dump."\n";
				}
				return "stored data:\n".$dumpList;
			}
			return "No data available: $opt $args[0]";
		}
		elsif($args[0] eq "Energy"){
			if(defined($hash->{helper}{devices}{data})){
				$dumpList = "";
				foreach my $devices(@{$hash->{helper}{devices}{data}}){
					$dumpList .= "DeviceId: ".$devices->{id}."\n";
					if(defined($devices->{energy})){
						Zendure_convertBool($devices->{energy});
						local $Data::Dumper::Deepcopy = 1;
						$dump = Dumper($devices->{energy});
						$dump =~ s{\A\$VAR\d+\s*=\s*}{};
					}
					$dumpList .= $dump."\n";
				}
				return "stored data:\n".$dumpList;
			}
			return "No data available: $opt $args[0]";
		}
		elsif($args[0] eq "Details"){
			if(defined($hash->{helper}{devices}{data})){
				$dumpList = "";
				foreach my $devices(@{$hash->{helper}{devices}{data}}){
					$dumpList .= "DeviceId: ".$devices->{id}."\n";
					if(defined($devices->{detail})){
						Zendure_convertBool($devices->{detail});
						local $Data::Dumper::Deepcopy = 1;
						$dump = Dumper($devices->{detail});
						$dump =~ s{\A\$VAR\d+\s*=\s*}{};
					}
					$dumpList .= $dump."\n";
				}
				return "stored data:\n".$dumpList;
			}
			return "No data available: $opt $args[0]";
		}
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
				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/properties/report:.* { json2nameValue(\$EVENT, 'properties_report_', \$JSONMAP, undef, 'packData') }\n";
				$text .= ".*/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}."/properties/report:.* { ashKeyRename(json2nameValue(\$EVENT,undef,undef,'packData'),'packData_(.*)_sn:(.*)','(\\d+)') }\n";
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
				$text .= "Output:30,60,90,100,200,300,400,500,600 iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/write {"properties":{"outputLimit"'.":\$EVTPART1}} \n";
				$text .= "Update:noArg iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/read {"properties":["getAll"]}'." \n";
				$text .= "Bypass:0,1,2 iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/write {"properties":{"passMode"'.":\$EVTPART1}} \n";
				$text .= "autoRecover:0,1 iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/write {"properties":{"autoRecover"'.":\$EVTPART1}} \n";
				$text .= "Buzzer:0,1 iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/write {"properties":{"buzzerSwitch"'.":\$EVTPART1}} \n";
				$text .= "minSoc:100,200,300,400,500 iot/".$hash->{helper}{productKey}."/".$hash->{helper}{deviceKey}.'/properties/write {"properties":{"minSoc"'.":\$EVTPART1}} \n";
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

# Attr #########################################################################
sub Zendure_Attr {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	# $cmd can be "del" or "set"
	# $name is device name
	# $attr_name and $attr_value are Attribute name and value
	my $hash = $main::defs{$name};
	
	$attr_value = "" if (!defined $attr_value);
	
	Log3 $name, 5, $name.": <Attr> Called for $attr_name : value = $attr_value";
	
	if($cmd eq "set") {
        if($attr_name eq "xxx") {
			# value testen
			#if($attr_value !~ /^yes|no$/) {
			#    my $err = "Invalid argument $attr_value to $attr_name. Must be yes or no.";
			#    Log 3, "xxxxx: ".$err;
			#    return $err;
			#}
		}
		elsif($attr_name eq "updateInterval") {
			unless ($attr_value =~ qr/^[0-9]+$/) {
				Log3 $name, 2, $name.": Invalid Time in attr $attr_name : $attr_value";
				return "Invalid Time $attr_value";
			} 
			InternalTimer(gettimeofday() + $attr_value, "Zendure_getUpdate", $hash) if($attr_value);
		} 

	}
	elsif($cmd eq "del"){
		#default wieder herstellen
		if($attr_name eq "updateInterval") {
			RemoveInternalTimer($hash, "Zendure_getUpdate"); 
		} 
	
	}
	return undef;
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
