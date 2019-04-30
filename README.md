# bodbridge
## Bridge between IGT Beverage on Demand (BOD) and Acres 4 Kai.

Listens for HTTP POST from BOD. BOD must be configured to send this POST to the IP address for machine running bodbridge on port 4567, eg. http://10.2.3.4:4567/bod

Sends Kai API request to create call based on drink order.

## INSTALLATION
This script must be run in a location with access to your Kai server at https://yoursitename.kailabor.com.

### 1. Install ruby and gems

Install Ruby, and the following gems:
  - sinatra
  - rest-client

eg. `sudo gem install sinatra rest-client`

bodbridge was developed with Ruby 2.3.1p112, sinatra 2.0.5 and rest-client 1.8.0.

### 2. Configure API credentials

Set up an API user in Kai. Place the sitename, username and password each on their own line in a file called "./kai_bod_api_credentials" relative to the working directory when running this script, eg.

```
rivervalleycasino
bodapiuser
SecretPassword123
```

### 3. Configure beverage-on-demand
Configure beverage-on-demand to provide HTTP POSTs to the system's IP address with the configured port number at the /bod endpoint, e.g. `http://10.2.3.4:4567/bod`

### 4. Configure calls in Kai
Create calls matching beverage menu items as desired. See "CALL CONFIGURATION" section below.

### 5. Install script
Install a systemd or other script as appropriate for your system to ensure bodbridge remains running.

Note that bodbridge writes helpful debug output to STDOUT, and error messages to STDERR.


## PORT CONFIGURATION

Default HTTP port for BOD postbacks: **4567**

The port number can be optionally specified as the first command line argument, e.g. `./bodbridge.rb 1234` will cause bodbridge to listen for HTTP POSTs on TCP 1234.

## CALL CONFIGURATION
bodbridge will use the name of the drink requested to create an appropriate call when possible. It will look for calls with the following names. It will use the first matching call it finds that is configured.

(\* indicates wildcard, matches are case insensitive)

 - \*Beverage\*coffee
 - \*Request\*coffee
 - Coffee\*beverage\*
 - Coffee\*request\*
 - Coffee
 - \*Beverage\*coffee\*
 - \*Request\*coffee\*
 - \*Coffee\*beverage\*
 - \*Coffee\*request\*
 - \*Coffee\*
 - Drink request
 - Beverage request
 - Service

If no matching calls are found, no call is created.

If multiple matching calls exist, the one whose name matches a pattern listed highest above will be used. If multiple calls exist for the same pattern, the one with the highest id_call_config is used.

The matched calls must be configured as machine-generated calls. If bodbridge's best match is a user-generated call, then an error will result and the call will not be dispatched. It is not necessary to have an actual valid event mapped to the calls that bodbridge maps drink requests to.

Be very careful to configure Kai call names to match the exact spelling of beverage menu items. For instance, if a drink is called "Dr. Pepper" in the menu, but "Dr Pepper" in Kai (note the missing dot), the call will not map over.

Names are not case sensitive, so "Dr. pepper" will map to "Dr. Pepper" without issue.

## MULTIPLE ITEMS IN ORDER
If an order contains multiple items, only the first item is used in selecting an appropriate id_call_config. All items (including the first and subsequent items) are listed in the description field supplied to the Kai API.

## TROUBLESHOOTING

### Problem: UnsupportedDrinkError exceptions

**Resolution**: Ensure that Kai call configuration has at least one call enabled that supports a beverage with the indicated name. See "CALL CONFIGURATION" section for more information.

### Problem: APIRequestError exceptions

**Resolution**: Ensure that Kai API user credentials are set up with Kai, and correctly specifeid in the ./kai_bod_api_credentials file. Also check that Kai API server is reachable from the machine running bodbridge as
`https://username:password@sitename.kailabor.com/api/v3`

### Problem: UnsupportedRequestFormatError exceptions

**Resolution**: Request format received from BOD is not understood by this script.

Ensure that bodbridge is receiving callbacks from supported version of BOD.

### Problem: Pepsi maps as Diet Pepsi

**Resolution**: Ensure that you have a properly-named Pepsi call. Otherwise, per the rules of name matching, Pepsi may match to a Diet Pepsi call due to the similarity in names.

### Problem: Orders create generic calls instead of item-specific calls

**Resolution**: Check that spelling of menu item matches spelling of call in Kai, and that the calls in Kai are configured as machine-generated events.

### Problem: Orders do not create calls

**Resolution**: Ensure that a machine-generated call in Kai is configured with the name "Drink Request". It does not matter which events map to this call, but it is highly recommended that you select an event that is never observed on your slot floor to avoid generating duplicate or mistaken calls.

If call configuration looks correct, then ensure that bodbridge is running. You can point your web browser at bodbridge, e.g. `http://10.2.3.4:4567/bod` (substituting in the correct IP address and port for your environment) and check to see if you get a response indicating that bodbridge is running at that address.

If bodbridge is running, check that Beverage-on-demand is configured to send a POST to bodbridge at that URL when drink orders are received. Consult your Beverage-on-demand documentation for more information.

If Beverage-on-demand is configured to send this POST request, ensure that there are no routing issues such as firewalls preventing the Beverage-on-demand server from reaching the bodbridge URL.

If the Beverage-on-demand server can reach bodbridge, check that the server running bodbridge has correctly configured the site name, API username and API password as described in "Configure API Credentials" above. Reset the API user's password if needed to ensure that the username and password have not been changed since configuring bodbridge.

If bodbridge is configured with the correct site name, API username and password, ensure that the server running bodbridge can reach https://sitename.kailabor.com, where "sitename" is your configured Kai site name.

If the server running bodbridge can reach https://sitename.kailabor.com, use `nslookup` or `dig` or a similar tool to ensure that the DNS entry for `sitename.kailabor.com` resolves to the expected IP address, and not an IP address for a server in a different environment (e.g. you may be reaching your test environment when you intend to be reaching your production site).

If no issues are found in any of these steps, check the log output of bodbrdige (as written to stdout and stderr) for more information.

### Problem: 

## AUTHOR

Completed on contract for Acres Bonusing.

Jonas Acres, jonas@acrescrypto.com, 702-481-4146

