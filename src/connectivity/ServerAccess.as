package connectivity
{
	import flash.events.Event;
	import flash.events.HTTPStatusEvent;
	import flash.events.IOErrorEvent;
	import flash.net.URLLoader;
	import flash.net.URLLoaderDataFormat;
	import flash.net.URLRequest;
	import flash.net.URLRequestHeader;
	import flash.net.URLRequestMethod;
	import flash.net.URLVariables;
	
	import mx.utils.Base64Encoder;
	import mx.utils.StringUtil;
	
	import connectivity.Response;
	
	/**
	 * This class contains methods to wrap interactions with the server.
	 */
	public class ServerAccess
	{
		//todo: caching
		//todo: objects? what do we store and assume is availale?  return types?
		//tumblre update with my sheet
		
		// URL to server
		private static const hostname:String = "https://nodejs-collective-server.herokuapp.com";
		
		// Cached session info
		private static var userId:String;
		private static var email:String;
		private static var password:String;
		
		/**
		 * Constructor 
		 */
		public function ServerAccess()
		{
			// not used
		}
		
		// ========================================================================================
		// INTERNAL FUNCTIONS
		// ========================================================================================
		
		// from le nets java2s.com
		private static function toTitleCase( original:String ):String {
			var words:Array = original.split( " " );
			for (var i:int = 0; i < words.length; i++) {
				words[i] = toInitialCap( words[i] );
			}
			return ( words.join( " " ) );
		}
		private static function toInitialCap( original:String ):String {
			return original.charAt( 0 ).toUpperCase(  ) + original.substr( 1 ).toLowerCase(  );
		}
		
		/**
		 * Converts data to a JSON object if it is a JSON string.  If not, it does nothing.
		 * The data (converted or no) is returned.
		 */
		private static function convertAnyJSON(data:String):Object 
		{
			var converted:Object;
			// Only proceed if there's any actual data...
			if (data != null) {
				try {
					// Assume the data is a JSON string and try and parse it.
					converted = JSON.parse(data);
				} catch (error:Error) {
					// No JSON to parse, just use the data as-is.	
					converted = data;
				}
			}
			return converted;
		}
	
		private static function isInvalidLocation(lat:Number, lon:Number):Boolean 
		{
			return (lat < -90 || lat > 90 || lon < -180 || lon > 180);
		}
		
		private static function isInvalidEmail(email:String):Boolean 
		{
			return (!email.match(/^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,4}$/));
		}
		
		private static function isInvalidCity(city:String):Boolean 
		{
			return !city.match(/^[A-Za-z]{3,20}\ ?([A-Za-z]{3,20})?$/);
		}
		
		private static function isInvalidPostcode(postcode:String):Boolean 
		{
			return !postcode.match(/^[1-9][0-9]{3}$/);
		}
		
		private static function addAuthenticationHeader(request:URLRequest, email:String, 
														password:String):void
		{
			// Get cached info if email null
			if (email == null) 	
			{
				if (ServerAccess.email == null || ServerAccess.password == null)
				{
					throw new Error("addAuthenticationHeader: no authentication info supplied. " +
						"authenticate() needs to be called before calling most methods!");
				}
				email = ServerAccess.email;
				password = ServerAccess.password;
			}
			
			/*
				So an awesome thing about Adobe Air: you can't use authorisation headers in GET 
				requests. Why? "browser limitations". Fucked if I know what that means.  Therefore
				we need to use POST whenever an authorisation header is used, yay.
				
				Also, Authorization is a header that can't be used outside of the application 
				security sandbox. This appears to just be fancyspeak for "the application" so we're
				alright.  
			*/
			request.method = URLRequestMethod.POST;
			
			// Encode the email+password into a base64 string
			var encoder:Base64Encoder = new Base64Encoder();        
			encoder.insertNewLines = false; // it tries to insert new lines :\
			encoder.encode(email+":"+password);
			
			// Include it in an Authorization header and attach it to the request. 
			var header:String = encoder.toString();
			var credsHeader:URLRequestHeader = 
				new URLRequestHeader("Authorization", "Basic " + header);
			trace("auth header: " + header);
			request.requestHeaders.push(credsHeader);
			
			// Dirty hack time!  Because this is a dirty language...   
			// POST requests without data are converted to GET. Why? No fucking good reason that I
			// can see. :|
			request.data = "{}";
			request.contentType = "application/json";
			// If any data actually needs to be posted, it needs to be set after this is called.
		}
		
		// ========================================================================================
		// PUBLIC FUNCTIONS FOR INTERACTION WITH SERVER
		// ========================================================================================

		/**
		 * Attempts to register a user with the server.  
		 * 	firstName: 	The first name of the user
		 * 	lastName: 	The last name of the user
		 * 	lat: 		The latitude of the user (must be valid)
		 * 	lon: 		The longitude of the user (must be valid)
		 * 	address:	The address of the user minus city and postcode
		 * 	city:		The city of the user (must be valid)
		 * 	postcode:	The postcode of the user (must be valid)
		 * 	email:		The email of the user (must be valid)
		 * 	password:	The password of the user
		 * 	callback:	The function to call when the attempt is complete.
		 * 
		 * The 'callback' function will be called and passed a 'Response' object as its argument. 
		 * SUCCESS: Response will indicate success and contain a JSON object containing user info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function register(firstName:String, 
										lastName:String, 
										lat:Number, 
										lon:Number,
										address:String, 
										city:String, 
										postcode:String, 
										email:String,
		         						password:String,
										callback:Function):void 
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			// Location:
			if (isInvalidLocation(lat,lon))
				response = new Response(false, "Invalid location.");			
			// Email:
			email = StringUtil.trim(email).toLowerCase();
			if (isInvalidEmail(email))
				response = new Response(false, "Invalid email.");			
			// City:			
			city = toTitleCase(StringUtil.trim(city));
			if(isInvalidCity(city))
				response = new Response(false, "Invalid city.");			
			// Postcode:
			postcode = StringUtil.trim(postcode);
			if (isInvalidPostcode(postcode))
				response = new Response(false, "Invalid postcode.");			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Construct JSON body
			var bodyObject:Object = {
				firstName:firstName,
				lastName:lastName,
				location:{
					lat:lat, 
					lon:lon
				},
				address:address,
				city:city,
				postcode:postcode,
				email:email,
				password:password			
			};
			var body:String = JSON.stringify(bodyObject);
			
			// Construct URL request
			var request:URLRequest = new URLRequest(hostname + "/register");
			request.contentType = "application/json";
			request.method = URLRequestMethod.POST;
			request.data = body;
			
			// Construct URL loader 
			var loader:URLLoader = new URLLoader();
			loader.dataFormat = URLLoaderDataFormat.TEXT;
			
			// Add listener functions for various URL events. 
			loader.addEventListener(Event.COMPLETE, completeHandler);
			loader.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);

			// Load the request
			try {
				// This loads the request asynchronously. Event functions will fire
				// as appropriate.
				loader.load(request);
			} catch (error:Error) {
				// The errors that can be thrown are not tied to the server's responses
				// but are rather things like out of memory, syntax errors, etc. so we
				// can consider these to be rare occurrences.
				trace("Unable to load requested document.");
				response = new Response(false, "Internal Error!");
				callback(response);
				return;
			}
			
			// --- EVENT HANDLING -----------------------------------------------------------------
			// Annoyingly, these cannot be standardised at the top of this class as they must call
			// the appropriate callback function, which can't be passed in as a parameter because
			// the function is executed as part of an event.
			
			// Called when data is loaded successfully.
			function completeHandler(event:Event):void {
				var loader:URLLoader = URLLoader(event.target);
				trace("register completeHandler: " + loader.data);				
				var data:Object = convertAnyJSON(loader.data);
				
				// Save the user id for this session
				ServerAccess.userId = data._id;
				
				// Callback function: pass response indicating success along with the data, if any.
				response = new Response(true, data);
				callback(response);
			}
			
			// Called when an error occurs for some reason, including a bad status code.
			// This event doesn't contain the status code for some messed up reason.
			function ioErrorHandler(event:IOErrorEvent):void {				
				var loader:URLLoader = URLLoader(event.target);
				trace("register ioErrorHandler: " + event + ", data: " + loader.data);

				// Callback function: pass response indicating failure along with the data, if any.
				response = new Response(false, convertAnyJSON(loader.data));
				callback(response);
			}
		}
		
		/**
		 * Attempts to authenticate the given email and password with the server.  If successful,
		 * the username and password will be stored and used with calls to other methods that
		 * require authentication.
		 * 
		 * 	email: 		The user's email, will be converted to lower case
		 * 	password:	The user's password 
		 * 	callback:	The function to call when the attempt is complete.
		 * 
		 * The 'callback' function will be called and passed a 'Response' object as its argument. 
		 * SUCCESS: Response will indicate success and contain a JSON object containing user info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function authenticate(email:String, 
											password:String, 
											callback:Function):void
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			// Email:
			email = StringUtil.trim(email).toLowerCase();
			if (isInvalidEmail(email))
				response = new Response(false, "Invalid email.");
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
						
			// Construct URL request
			var request:URLRequest = new URLRequest(hostname + "/authenticate");
			addAuthenticationHeader(request, email, password); // Authentication required			
			
			// Construct URL loader 
			var loader:URLLoader = new URLLoader();
			loader.dataFormat = URLLoaderDataFormat.TEXT;
			loader.addEventListener(Event.COMPLETE, completeHandler);
			loader.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
			
			// Load the request
			try {
				loader.load(request);
			} catch (error:Error) {
				trace("Unable to load requested document.");
				response = new Response(false, "Internal Error!");
				callback(response);
				return;
			}
			
			// --- EVENT HANDLING -----------------------------------------------------------------
			
			// Called when data is loaded successfully.
			function completeHandler(event:Event):void {
				var loader:URLLoader = URLLoader(event.target);
				trace("authenticate completeHandler: " + loader.data);
				var data:Object = convertAnyJSON(loader.data);
				
				// Save data
				ServerAccess.userId = data._id;
				ServerAccess.email = email;
				ServerAccess.password = password;
				
				response = new Response(true, data);
				callback(response);
			}
			
			// Called when an error occurs for some reason, including a bad status code.
			function ioErrorHandler(event:IOErrorEvent):void {				
				var loader:URLLoader = URLLoader(event.target);
				trace("authenticate ioErrorHandler: " + event + ", data: " + loader.data);
				response = new Response(false, convertAnyJSON(loader.data));
				callback(response);
			}
		}
		
		/**
		 * Attempts to get a user's profile from the server.
		 * Requires that authenticate() have been called at least once.
		 * 
		 *  userId:		The user's id (optional, use null to use current user)
		 * 	callback: 	The function to call when the attempt is complete.
		 * 
		 * The 'callback' function will be called and passed a 'Response' object as its argument. 
		 * SUCCESS: Response will indicate success and contain a JSON object containing user info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function getProfile(userId:String, 
										  callback:Function):void
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			// UserID:
			if(userId != null && userId.length == 0)
				response = new Response(false, "Invalid user ID.");
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Cached info
			if (userId == null) 	userId = ServerAccess.userId;
			
			// Construct URL request
			var request:URLRequest = new URLRequest(hostname + "/getProfile/"+userId);
			addAuthenticationHeader(request, null, null); // Assume cached info exists.	
			request.contentType = "application/json";
			
			// Construct URL loader 
			var loader:URLLoader = new URLLoader();
			loader.dataFormat = URLLoaderDataFormat.TEXT;
			loader.addEventListener(Event.COMPLETE, completeHandler);
			loader.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
			
			// Load the request
			try {
				loader.load(request);
			} catch (error:Error) {
				trace("Unable to load requested document.");
				response = new Response(false, "Internal Error!");
				callback(response);
				return;
			}
			
			// --- EVENT HANDLING -----------------------------------------------------------------
			
			// Called when data is loaded successfully.
			function completeHandler(event:Event):void {
				var loader:URLLoader = URLLoader(event.target);
				trace("getProfile completeHandler: " + loader.data);
				response = new Response(true, convertAnyJSON(loader.data));
				callback(response);
			}
			
			// Called when an error occurs for some reason, including a bad status code.
			function ioErrorHandler(event:IOErrorEvent):void {				
				var loader:URLLoader = URLLoader(event.target);
				trace("getProfile ioErrorHandler: " + event + ", data: " + loader.data);
				response = new Response(false, convertAnyJSON(loader.data));
				callback(response);
			}
		}
		
		/**
		 * Attempts to edit a user profile's profile. Only supplied information is updated, so
		 * you can update specific parts of a user's profile without touching the rest.
		 * Requires that authenticate() have been called at least once.
		 * 
		 * 	userId:		The user's id (optional, use null to use current user)
		 * 	callback: 	The function to call when the attempt is complete.
		 * 
		 * Optional parameters to update: (Use 'null' if you don't want these to change, or NaN
		 * 								   for lat / lon)		 
		 * 	firstName: 	The first name of the user
		 * 	lastName: 	The last name of the user
		 * 	lat: 		The latitude of the user (must be valid)
		 * 	lon: 		The longitude of the user (must be valid)
		 * 	address:	The address of the user minus city and postcode
		 * 	city:		The city of the user (must be valid)
		 * 	postcode:	The postcode of the user (must be valid)
		 * 	password:	The password of the user
		 *   
		 * The 'callback' function will be called and passed a 'Response' object as its argument. 
		 * SUCCESS: Response will indicate success and contain a JSON object containing user info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function editProfile(userId:String, 
										   firstName:String, 
										   lastName:String, 
										   lat:Number, 
										   lon:Number, 
										   address:String, 
										   city:String, 
										   postcode:String, 
										   password:String, 
										   callback:Function):void 
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			// UserID:
			if(userId != null && userId.length == 0)
				response = new Response(false, "Invalid user ID.");
			// Location:
			if (!isNaN(lat) && !isNaN(lon) && isInvalidLocation(lat,lon))
				response = new Response(false, "Invalid location.");			
			// Email:
			if (email != null) 
			{
				email = StringUtil.trim(email).toLowerCase();
				if (isInvalidEmail(email))
					response = new Response(false, "Invalid email.");			
			}
			// City:	
			if (city != null)
			{
				city = toTitleCase(StringUtil.trim(city));
				if(isInvalidCity(city))
					response = new Response(false, "Invalid city.");			
			}
			// Postcode:
			if (postcode != null) 
			{
				postcode = StringUtil.trim(postcode);
				if (isInvalidPostcode(postcode))
					response = new Response(false, "Invalid postcode.");			
			}
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Cached info
			if (userId == null) 	userId = ServerAccess.userId;
			
			// Construct JSON body
			var bodyObject:Object = new Object();
			if (firstName != null)	bodyObject["firstName"] = firstName;
			if (lastName != null)	bodyObject["lastName"] = lastName;
			if (!isNaN(lat) && !isNaN(lon))				
									bodyObject["location"] = { lat:lat, lon:lon };
			if (address != null)	bodyObject["address"] = address;
			if (city != null)		bodyObject["city"] = city;
			if (postcode != null)	bodyObject["postcode"] = postcode;
			if (password != null)	bodyObject["password"] = password;
			
			var body:String = JSON.stringify(bodyObject);
			
			// Construct URL request
			var request:URLRequest = new URLRequest(hostname + "/updateProfile/"+userId);
			addAuthenticationHeader(request, null, null); // Assume cached info exists.
			request.contentType = "application/json";
			request.data = body;
			
			// Construct URL loader 
			var loader:URLLoader = new URLLoader();
			loader.dataFormat = URLLoaderDataFormat.TEXT;
			loader.addEventListener(Event.COMPLETE, completeHandler);
			loader.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
			
			// Load the request
			try {
				loader.load(request);
			} catch (error:Error) {
				trace("Unable to load requested document.");
				response = new Response(false, "Internal Error!");
				callback(response);
				return;
			}
			
			// --- EVENT HANDLING -----------------------------------------------------------------
			
			// Called when data is loaded successfully.
			function completeHandler(event:Event):void {
				var loader:URLLoader = URLLoader(event.target);
				trace("editprofile completeHandler: " + loader.data);

				// Save data
				if (email != null) 		ServerAccess.email = email;
				if (password != null) 	ServerAccess.password = password;
				
				// Callback function: pass response indicating success along with the data, if any.
				response = new Response(true, convertAnyJSON(loader.data));
				callback(response);
			}
			
			// Called when an error occurs for some reason, including a bad status code.
			function ioErrorHandler(event:IOErrorEvent):void {				
				var loader:URLLoader = URLLoader(event.target);
				trace("editprofile ioErrorHandler: " + event + ", data: " + loader.data);

				// Callback function: pass response indicating failure along with the data, if any.
				response = new Response(false, convertAnyJSON(loader.data));
				callback(response);
			}
		}
		
		/**
		 * Gets resources within radius metres of the given latitude+longitude. Can add filters.
		 * 
		 * Returns an array of resource objects.
		 */
		public static function getResourcesNearby(lat:Number, lng:Number, radius:int, filters:String):Object
		{
			return null;
		}
		
		/**
		 * Gets resources offered by the given user.
		 * 
		 * Returns an array of resource objects.
		 */
		public static function getResourcesOfferedBy(userId:String):Object
		{
			return null;
		}
		
		/**
		 * Gets the resource with the given id.
		 * 
		 * Returns a resource object.
		 */
		public static function getResource(resourceId:String):Object
		{
			return null;
		}
		
		/**
		 * Adds a resource to the database with the given info.
		 */
		public static function addResource(userId:String, resourceId:String, resourceType:String, lat:Number, lng:Number,
										   title:String, description:String, 
										   ownerId:String, firstName:String, lastName:String,
										   points:int, wantedList:String, image:Object):Boolean
		{
			return false;
		}
		
		/**
		 * Edits an existing resource with the given id.  Any other non-null parameter will be sent through as an
		 * change for the resource.
		 */
		public static function editResource(userId:String, resourceId:String, resourceType:String, lat:Number, lng:Number,
										   title:String, description:String, 
										   points:int, wantedList:String, image:Object):Boolean
		{
			return false;
		}
		
		/**
		 * Creates a trade with the given info.
		 */
		public static function createTrade(userId:String, resourceId:String, message:String, forPoints:Boolean):Object
		{
			return null;
		}
		
		/**
		 * Gets all trades associated with the given user.
		 */
		public static function getTrades(userId:String):Object
		{
			return null;
		}
		
		/**
		 * Actions a trade.
		 * TODO: enum action
		 */
		public static function actionTrade(userId:String, tradeId:String, action:Object):Boolean
		{
			return false;
		}
		
		/**
		 * Actions a trade.
		 * TODO: enum action
		 */
		/*public static function actionTrade(userId:String, tradeId:String, action:Object):Boolean
		{
			return false;
		}*/
		
		/**
		 * Gets available actions for a trade.
		 * TODO: enum actions
		 */
		public static function getAvailableActions(userId:String, tradeId:String):Object
		{
			return false;
		}
		
		/**
		 * Posts a message on a trade
		 */
		public static function postMessage(userId:String, tradeId:String, message:String):Object
		{
			return null;
		}
		
		/**
		 * Gets available actions for a trade.
		 * TODO: enum actions
		 */
		/*public static function getAvailableActions(userId:String, tradeId:Object):Object
		{
			return false;
		}*/
	}
}