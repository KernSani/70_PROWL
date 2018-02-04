# $Id$
##############################################################################
#
#     70_Prowl.pm
#     An FHEM Perl module to send push messages via https://www.prowlapp.com/
#
#     Copyright by Oli Merten
#     e-mail: oli.merten at gmail.com
#
#     This file luckily is not part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
# 	  Changelog:
#	  0.2.01: fixed duplicate variable declaration, don't delete error readings 
#	  0.2.02: added documentation, fixed issue with internal timer executing multiple calls 
##############################################################################

package main;

use strict;
use warnings;
use HttpUtils;
use XML::Simple qw(:strict);
use Data::Dumper;

my $version     = "0.2.02";
my $apiUrl      = "https://api.prowlapp.com/publicapi/";
my $providerkey = '897971bd76fee7cdeed7a119f5e079984be41cfd';

###################################
sub Prowl_Initialize($) {
    my ($hash) = @_;

    # Module specific attributes
    my @prowl_attr =
      ( "default_prio", "default_event", "default_application", "apikey" );

    $hash->{GetFn}    = "Prowl_Get";
    $hash->{SetFn}    = "Prowl_Set";
    $hash->{DefFn}    = "Prowl_Define";
    $hash->{UndefFn}  = "Prowl_Undefine";
    $hash->{AttrFn}   = "Prowl_Attr";
    $hash->{AttrList} = join( " ", @prowl_attr ) . " " . $readingFnAttributes;

}

###################################
sub Prowl_Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    my $usage = "syntax: define <name> Prowl";

    my ( $name, $type ) = @a;
    if ( int(@a) != 2 ) {
        return $usage;
    }

    Log3 $name, 3, "Prowl defined $name $type";

    $hash->{VERSION} = $version;
    $hash->{APIURL}  = $apiUrl;
    $hash->{STATE}   = "Please set attribute apikey";

    
    if ($init_done){
    	Prowl_GetUpdate($hash);
    }

    return undef;
}

###################################
sub Prowl_Undefine($$) {

    my ( $hash, $name ) = @_;

    RemoveInternalTimer($hash);

    return undef;
}
###################################
sub Prowl_Set($@) {
    my ( $hash, @a ) = @_;
    my $name  = $hash->{NAME};
    my $state = $hash->{STATE};

    

    return "No Argument given" if ( !defined( $a[1] ) );
	
	Log3 $name, 5, "Prowl $name: called function Prowl_Set() with" . Dumper(@a);
    
	my $usage = "Unknown argument " . $a[1] . ", choose one of msg";
	
    # Apikey
    #if ( $a[1] eq "apikey" ) {
    #	readingsBeginUpdate($hash);
    #	readingsBulkUpdate( $hash, "oldAPIKey", $hash->{DEF});
    #	readingsEndUpdate( $hash, 1 );
    #	$hash->{DEF} = $a[2];
    #	Prowl_ValidateApikey($hash, $a[2]);
    # }
    # Send a message
    if ( $a[1] eq "msg" ) {
        return Prowl_SendMessage( $hash, splice( @a, 2 ) );
    }

    # return usage hint
    else {
        return $usage;
    }
    return undef;
}
###################################
sub Prowl_Get($@) {
    my ( $hash, @a ) = @_;
    my $name  = $hash->{NAME};
    my $state = $hash->{STATE};

    return "No Argument given" if ( !defined( $a[1] ) );
	
	Log3 $name, 5,
      "Prowl $name: called function Prowl_Get() with " . Dumper(@a);

    my $usage =
      "Unknown argument " . $a[1] . ", choose one of token:noArg apikey:noArg update:noArg";
    my $error = undef;

    # Apikey (after token)
    if ( $a[1] eq "apikey" ) {
        $error = Prowl_ApiKey($hash);
    }

    # get a token
    elsif ( $a[1] eq "token" ) {
        $error = Prowl_GetToken($hash);
    }
	elsif  ( $a[1] eq "update" ) {
		$error = Prowl_GetUpdate($hash);
	}

    # return usage hint
    else {
        return $usage;
    }
    return $error;
}
###################################
sub Prowl_Attr($) {

    my ( $cmd, $name, $aName, $aVal ) = @_;

    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value

    if ( $cmd eq "set" ) {

        # Priroity has to be between -2 and 2
        if ( $aName eq "default_prio" ) {
            if ( $aVal > 2 or $aVal < -2 ) {
                Log3 $name, 3,
                  "$name: $aName is a value between -2 and +2: $aVal";
                return "Attribute " . $aName
                  . " has to be a value between -2 and +2";
            }
        }
        elsif ( $aName eq "apikey" ) {
            my $hash = $defs{$name};
            Log3 $name, 3, "$name: Apikey $aVal set";
            Prowl_ValidateApikey( $hash, $aVal );
        }
    }
    elsif ( $cmd eq "del" ) {
        if ( $aName eq "apikey" ) {
            my $hash = $defs{$name};
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "state", "set Attribute apikey first" );
            readingsEndUpdate( $hash, 1 );
        }
    }

    return undef;
}

###################################
# Helper Functions                #
###################################
sub Prowl_GetToken($) {
    my ($hash) = @_;
    my $method = "retrieve/token";
    my $url = $hash->{APIURL} . "/" . $method . "?providerkey=" . $providerkey;

    Prowl_SendCommand( $hash, $url );
    return undef;
}
###################################
sub Prowl_ApiKey($) {
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my $method = "retrieve/apikey";
    my $token = ReadingsVal( $name, "token", 0 );
    if ( !$token ) {
        Log3 $name, 3, "$name: Get Token first: $token";
        return "Execute 'Get token' first";
    }

    my $url =
        $hash->{APIURL} . "/" 
      . $method
      . "?providerkey="
      . $providerkey
      . "&token="
      . $token;

    Prowl_SendCommand( $hash, $url );
}

###################################
sub Prowl_ValidateApikey($$) {
    my ( $hash, $apikey ) = @_;
    my $name   = $hash->{NAME};
    my $method = "verify";

    my $url = $hash->{APIURL} . "/" . $method . "?apikey=" . $apikey;

    Prowl_SendCommand( $hash, $url );
}
###################################
sub Prowl_SendMessage($@) {
    my ( $hash, @a ) = @_;
    my $method = "add";
    my $name   = $hash->{NAME};

    my $msgStr = join( " ", @a );

    Log3 $name, 5, "Prowl $name received $msgStr";
    my ( $desc, $prio, $event, $app ) = split /:/, $msgStr;
    if ( !$desc ) {
        Log3 $name, 1, "Prowl $name Message requires a text";
        return "set msg: Message requires a text";
    }
    if ( !$prio ) {
        $prio = AttrVal( $name, "default_prio", "1" );
    }
    if ( !$event ) {
        $event = AttrVal( $name, "default_event", "Nachricht" );
    }
    if ( !$app ) {
        $app = AttrVal( $name, "default_application", "FHEM" );
    }

    my $apikey = AttrVal( $name, "apikey", undef );
    my $apikeystate = ReadingsVal( $name, "apiKeyState", "invalid" );

    if ( !$apikey || $apikeystate eq "invalid" ) {
        Log3 $name, 1, "Prowl $name: Set a valid apikey first";
        return "Set a valid apikey first $apikey:$apikeystate";
    }

    my $url = $hash->{APIURL} . "/" . $method . "?apikey=" . $apikey;
    $url .= "&application=" . uri_escape($app);
    $url .= "&event=" . uri_escape($event);
    $url .= "&priority=" . $prio;
    $url .= "&description=" . uri_escape($desc);
	Log3 $name, 3, "Prowl $name: Sending message $url";
    Prowl_SendCommand( $hash, $url );
    return undef;
}

###################################
sub Prowl_ValidateResult($) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

	readingsBeginUpdate($hash);

    # Connection Error
    if ( $err ne "" ) {
        Log3 $name, 3, "error while requesting " . $param->{url} . " - $err";
        readingsBulkUpdate( $hash, "lastError", $err );
        readingsBulkUpdate( $hash, "state",
            "Connection error (see error message)" );
    }
    elsif ( $data ne "" ) {
        Log3 $name, 5, "Prowl $name received: $data";
        my $ret = XMLin( $data, ForceArray => 1, KeyAttr => {} );

# Prowl returned error
# 400 Bad request, the parameters you provided did not validate, see ERRORMESSAGE.
# 401 Not authorized, the API key given is not valid, and does not correspond to a user.
# 406 Not acceptable, your IP address has exceeded the API limit.
# 409 Not approved, the user has yet to approve your retrieve request.
# 500 Internal server error, something failed to execute properly on the Prowl side.
        if ( $ret->{error} ) {
            my $error = $ret->{error}[0]{content};
            my $code  = $ret->{error}[0]{code};
            Log3 $name, 5, "Prowl $name: failed with error" . Dumper($ret);
            Log3 $name, 1, "Prowl $name: failed with error $error ($code)";
            readingsBulkUpdate( $hash, "lastError",     $error );
            readingsBulkUpdate( $hash, "lastErrorCode", $code );
            if ( $code == 401 or $code == 409 ) {
                readingsBulkUpdate( $hash, "state",
                    "invalid (see error message)" );
                readingsBulkUpdate( $hash, "apiKeyState", "invalid" );
            }
            else {
                readingsBulkUpdate( $hash, "state",
                    "failed (see error message)" );
            }
        }

        # Prowl returned success
        elsif ( $ret->{success} ) {
            Log3 $name, 5, "Prowl $name: was sucessfully called";
            my $remain  = $ret->{success}[0]{remaining};
            my $reset   = localtime( $ret->{success}[0]{resetdate} );
            my $resetts = $ret->{success}[0]{resetdate};
            readingsBulkUpdate( $hash, "remaining",    $remain );
            readingsBulkUpdate( $hash, "nextReset",    $reset );
            readingsBulkUpdate( $hash, ".nextResetTS", $resetts );
            readingsBulkUpdate( $hash, "state",        "ready" );
            readingsBulkUpdate( $hash, "apiKeyState",  "valid" );
            # my $retdel = CommandDeleteReading( undef, "$name lastError" );

            # if ($retdel) {
                # Log3 $name, 5, "$name: $retdel";
            # }
            # $retdel = CommandDeleteReading( undef, "$name lastErrorCode" );
            # if ($retdel) {
                # Log3 $name, 5, "$name: $retdel";
            # }

            # we retrieved a token or apikey
            if ( $ret->{retrieve} ) {
                my $token  = $ret->{retrieve}[0]{token};
                my $apikey = $ret->{retrieve}[0]{apikey};
                if ($token) {
                    Log3 $name, 5, "Prowl $name: Token $token received";
                    my $url = $ret->{retrieve}[0]{url};
                    readingsBulkUpdate( $hash, "token",       $token );
                    readingsBulkUpdate( $hash, "tokenUrl",    $url );
                    readingsBulkUpdate( $hash, "apiKeyState", "invalid" );
                    readingsBulkUpdate( $hash, "state",
                        "invalid (call [tokenUrl] to grant access)" );
                }
                elsif ($apikey) {
                    Log3 $name, 5, "Prowl $name: API-Key $apikey received";
                    $attr{$name}{apikey} = $apikey;
                    readingsBulkUpdate( $hash, "apiKeyState", "valid" );
                    readingsBulkUpdate( $hash, "state",       "ready" );
                    CommandDeleteReading( undef, "$name token" );
                    CommandDeleteReading( undef, "$name tokenUrl" );
                }

            }
        }
    }
    readingsEndUpdate( $hash, 1 );
	return undef;
}
###################################
sub Prowl_GetUpdate($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    RemoveInternalTimer($hash);
	
	my $nextupdate = gettimeofday() + 3600;
	
# We vaildate the apikey after resetdate (also to get update "remaining" reading)
    my $apikey = AttrVal( $name, "apikey", undef );
    my $reset_ts =
      ReadingsVal( $name, ".nextResetTS", time_str2num("2099-12-31 00:00:00") );

    if ( $apikey && ($reset_ts <= gettimeofday() )) {
        Prowl_ValidateApikey( $hash, $apikey );
		# validation is asynchronous so we'll have to wait a bit to get the results
		$nextupdate = gettimeofday() + 5;
    }
	elsif ( $apikey && ($reset_ts > gettimeofday() )) {
		$nextupdate = $reset_ts + 180;
	}

    # If we have a token, we remove it after 24 hours
    if (ReadingsVal($name, "token", undef)) {
		my $ts =
		  time_str2num(
			ReadingsTimestamp( $name, "token", "2098-12-31 23:59:59" ) );
		Log3 $name, 3, "Prowl $name: token timestamp: ".localtime($ts);
		$ts += 24 * 3600;
		
		if ( $ts < gettimeofday() ) {
			Log3 $name, 3, "Prowl $name: Delete Token".localtime($ts);
			CommandDeleteReading( undef, "$name token" );
			CommandDeleteReading( undef, "$name tokenUrl" );
		}
	}
    # set next timer
	Log3 $name, 5, "Prowl $name: NextTimer: " . localtime($nextupdate)."(".localtime($reset_ts).")";
    InternalTimer( $nextupdate, "Prowl_GetUpdate", $hash, 1 );

    
}
###################################
sub Prowl_SendCommand($$) {
    my ( $hash, $url ) = @_;
    my $name = $hash->{NAME};

    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "state", "sending" );
    readingsEndUpdate( $hash, 1 );

    Log3 $name, 5, "Prowl $name: sending URL $url";
    my $params = {
        url      => $url,
        hash     => $hash,
        method   => "GET",
        callback => \&Prowl_ValidateResult

    };

    HttpUtils_NonblockingGet($params);
}
 
=pod
=item device
=item summary Send messages via Prowl App
=item summary_DE Textnachrichten über die Prowl App versenden
=begin html

<a name="Prowl"></a>
<h3>Prowl</h3>
<ul>
  Prowl is a service to receive instant push notifications on your
  phone or tablet from a variety of sources.<br>
  You need an account to use this module.<br>
  For further information about the service see <a href="https://www.prowlapp.com/">https://www.prowlapp.com/</a>.<br>
	<br><br>
<a name="ProwlDefine"></a>
  <b>Define</b>
  <ul>
	<code>define &lt;devicename&gt; Prowl</code><br><br>
	This is sufficient to create the device. To make it functional an API key has to be maintained in attribute 'apikey" (see below).
  </ul>
  <a name="ProwlSet"></a>
  <b>Set</b>
  <ul>
	msg: the real purpose of the module - send messages. The msg command works as follows<br><br>
	<code>set &lt;devicename&gt; msg &lt;message&gt;:&lt;priority&gt;:&lt;event&gt;:&lt;application&gt;</code><br><br>
	Besides &lt;message&gt; all parameters are optional and will be replaced by default values (see below)
  </ul>	
<a name="ProwlGet"></a>
  <b>Get</b>
  <ul>
	token: only necessary if no Prowl APIKEY is available. Generates a token and a URL. By executing the URL (and if required login/registration) you grant access for the module. Get apikey has to be executed after that.<br>
	apikey: gets the API key generated via get token and saves it in the application. 
  </ul>
  
 <a name="ProwlReadings"></a>
  <b>Readings</b>
  <ul>
	apiKeyState: shows the state of the API key (valid or invalid)<br>
	lastError: shows the last error message<br>
	lastErrorCode: the latest error code received from prowl <br>
	remaining: remaining messages (out of 1000/hour)<br>
	nextReset: when will the message counter be reset to 1000?<br>
	state: current state of the module<br>
	token: A token generated via GET token <br>
	tokenUrl: URL, which has to be called in the browser to grant access for the module (if no API ke was entered earlier)<br>
  </ul>

<a name="ProwlAttributes"></a>
  <b>Attributes</b>
  <ul>
	apikey: Prowl API Key - either existing already or generated via Get token/Get apikey<br>
	default_application: Default value for &lt;application&gt;, if not set:"FHEM"<br>
	default_event: Default value for &lt;event&gt;, if not set: "Nachricht"<br>
	default_prio: Default value for &lt;priority&gt;, if not set "0"<br>
</ul>
</ul>

=end html

=begin html_DE

<a name="Prowl"></a>
<h3>Prowl</h3>
<ul>
  Prowl ist ein Dienst, um Benachrichtigungen von einer Vielzahl
  von Quellen auf Deinem Smartphone oder Tablet zu empfangen.<br>
  Du brauchst einen Account um dieses Modul zu verwenden.<br>
  Weitere Informationen zu Prowl erh&auml;ltst du unter <a href="https://www.prowlapp.com/">https://www.prowlapp.com/</a>.<br>
  <br><br>
<a name="ProwlDefine"></a>
  <b>Define</b>
  <ul>
	<code>define &lt;devicename&gt; Prowl</code><br><br>
	Damit ist das device definiert, um es funktionsf&auml;hig zu machen mu&szlig; ein Api-Key im Attribut apikey (s.u.) gepflegt werden
  </ul>
  <a name="ProwlSet"></a>
  <b>Set</b>
  <ul>
	msg: Der eigentliche Sinn des Moduls - Nachrichten versenden. Der msg Befehl ist folgendermassen aufgebaut:<br><br>
	<code>set &lt;devicename&gt; msg &lt;Nachricht&gt;:&lt;Priorit&auml;t&gt;:&lt;Event&gt;:&lt;Applikation&gt;</code><br><br>
	Ausser &lt;Nachricht&gt; sind alle Parameter optional und werden ggf. durch default-Werte ersetzt(s.u.)
  </ul>	
<a name="ProwlGet"></a>
  <b>Get</b>
  <ul>
	token: Nur notwendig wenn kein Prowl APIKEY vorhanden ist. Erzeugt ein Token und eine URL. Durch ausf&uuml;hren der URL (und ggf. Anmeldung/Registrierung) wird dem Modul Zugriff gew&auml;hrt. Danach muss get apikey ausgef&uuml;hrt werden.&lt;br&gt;
	apikey: holt den durch get token generierten apikey ab und speichert ihn in der Applikation. 
  </ul>

<a name="ProwlReadings"></a>
  <b>Readings</b>
  <ul>
	apiKeyState: zeigt den aktuellen Status des Api-Keys an (valid oder invalid)<br>
	lastError: Zeigt die letzte aufgetretene Fehlermeldung<br>
	lastErrorCode: Der von Prowl zurück gemeldete Errorcode <br>
	remaining: Verbleibende Benachrichtigungen (von 1000/Stunde)<br>
	nextReset: Wann wird der Zähler wieder auf 1000 gesetzt<br>
	state: aktueller Status des Moduls<br>
	token: Ein durch GET token generiertes token<br>
	tokenUrl: URL, die im Browser aufgerufen werden muss, um dem Modul Zugriffsrechte zu geben (sofern kein bereits vorhandener eigener API Key eingegeben wurde)<br>
  </ul>

<a name="ProwlAttributes"></a>
  <b>Attribute</b>
  <ul>
	apikey: Prowl Api-Key - entweder bereits vorhanden oder durch Get token/Get apikey erzeugt <br>
	default_application: Default Wert für &lt;Applikation&gt;, wenn nicht gesetzt "FHEM"<br>
	default_event: Default Wert für &lt;Event&gt;, wenn nicht gesetzt "Nachricht"<br>
	default_prio: Default Wert für &lt;Priorität&gt;, wenn nicht gesetzt "0"<br>
</ul>
</ul>

=end html_DE
=cut

