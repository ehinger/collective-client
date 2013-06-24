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
			request.requestHeaders.push(credsHeader);
			
			// Dirty hack time!  Because this is a dirty language...   
			// POST requests without data are converted to GET. Why? No fucking good reason that I
			// can see. :|
			request.data = "{}";
			request.contentType = "application/json";
			// If any data actually needs to be posted, it needs to be set after this is called.
		}
		
		/**
		 * Provides a standard way to load a URLRequest.  This function will load the request
		 * and callback with an appropriate Response containing the data from the server, converted
		 * to a JSON object tree if applicable.  It also allows for onSuccess and onFailure event
		 * hooks to be passed through.
		 */
		private static function loadRequest(request:URLRequest,
											callback:Function, 
											onSuccess:Function = null, 
											onFailure:Function = null):void
		{
			var response:Response;
			
			// Construct URL loader 
			var loader:URLLoader = new URLLoader();
			loader.dataFormat = URLLoaderDataFormat.TEXT;
			loader.addEventListener(Event.COMPLETE, completeHandler);
			loader.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
			
			// Load the request
			try {
				// This loads the request asynchronously. Event functions will fire
				// as appropriate.
				trace("Loading request "+request.url);
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

			// Called when data is loaded successfully.
			function completeHandler(event:Event):void {
				var loader:URLLoader = URLLoader(event.target);
				trace("completeHandler: " + loader.data);				
				var data:Object = convertAnyJSON(loader.data);
				
				// Call onSuccess function
				if (onSuccess != null)
					onSuccess(data);
				
				// Callback function: pass response indicating success along with the data, if any.
				if (callback != null)
				{
					response = new Response(true, data);
					callback(response);
				}
			}
			
			// Called when an error occurs for some reason, including a bad status code.
			// This event doesn't contain the status code for some messed up reason.
			function ioErrorHandler(event:IOErrorEvent):void {				
				var loader:URLLoader = URLLoader(event.target);
				trace("ioErrorHandler: " + event + ", data: " + loader.data);
				var data:Object = convertAnyJSON(loader.data);
				
				// Call onFailure function
				if (onFailure != null)
					onFailure(data);
				
				// Callback function: pass response indicating failure along with the data, if any.
				if (callback != null)
				{
					response = new Response(false, data);
					callback(response);
				}
			}
		}
		
		// ========================================================================================
		// PUBLIC FUNCTIONS FOR INTERACTION WITH SERVER
		// ========================================================================================

		/**
		 * Gets the current user's userId.
		 * Requires that authenticate() have been called at least once.
		 */
		public static function getUserId():String {
			return userId;
		}
		
		/**
		 * Attempts to register a user with the server.  
		 * 	firstName: 	The first name of the user
		 * 	lastName: 	The last name of the user
		 * 	lat: 		The latitude of the user
		 * 	lon: 		The longitude of the user
		 * 	address:	The address of the user minus city and postcode
		 * 	city:		The city of the user 
		 * 	postcode:	The postcode of the user 
		 * 	email:		The email of the user
		 * 	password:	The password of the user
		 * 	callback:	The function to call when the attempt is complete.
		 * 
		 * The 'callback' function will be called and passed a 'Response' object as its argument. 
		 * SUCCESS: Response will indicate success and contain a JSON object containing info.
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
			
			email = StringUtil.trim(email).toLowerCase();
			postcode = StringUtil.trim(postcode);
			city = toTitleCase(StringUtil.trim(city));
			
			if (isInvalidLocation(lat,lon))	response = new Response(false, "Invalid location.");			
			if (isInvalidEmail(email))		response = new Response(false, "Invalid email.");					
			if (isInvalidCity(city))		response = new Response(false, "Invalid city.");			
			if (isInvalidPostcode(postcode))response = new Response(false, "Invalid postcode.");	
			
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
			
			// Load request and callback.
			loadRequest(request, callback, onSuccess);
			
			// Handle events.
			function onSuccess(data:Object):void {
				// Save the user id for this session
				ServerAccess.userId = data._id;
			}
			function onFailure(data:Object):void {}
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
		 * SUCCESS: Response will indicate success and contain a JSON object containing info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function authenticate(email:String, 
											password:String, 
											callback:Function):void
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			email = StringUtil.trim(email).toLowerCase();
						
			if (isInvalidEmail(email))		response = new Response(false, "Invalid email.");	
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
						
			// Construct URL request
			var request:URLRequest = new URLRequest(hostname + "/authenticate");
			addAuthenticationHeader(request, email, password); // Authentication required			
			
			// Load request and callback.
			loadRequest(request, callback, onSuccess);
			
			// Handle events.
			function onSuccess(data:Object):void {
				// Save user data
				ServerAccess.userId = data._id;
				ServerAccess.email = email;
				ServerAccess.password = password;
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
		 * SUCCESS: Response will indicate success and contain a JSON object containing info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function getProfile(userId:String, 
										  callback:Function):void
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
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
			
			// Load request and callback.
			loadRequest(request, callback);
		}
		
		/**
		 * Attempts to edit a user profile's profile. Only supplied information is updated, so
		 * you can update specific parts of a user's profile without touching the rest.
		 * Requires that authenticate() have been called at least once.
		 * 
		 * 	callback: 	The function to call when the attempt is complete.
		 * 
		 * Optional parameters to update: (Use 'null' if you don't want these to change, or NaN
		 * 								   for lat / lon)		 
		 * 	firstName: 	The first name of the user
		 * 	lastName: 	The last name of the user
		 * 	lat: 		The latitude of the user 
		 * 	lon: 		The longitude of the user 
		 * 	address:	The address of the user minus city and postcode
		 * 	city:		The city of the user 
		 * 	postcode:	The postcode of the user 
		 * 	password:	The password of the user
		 *   
		 * The 'callback' function will be called and passed a 'Response' object as its argument. 
		 * SUCCESS: Response will indicate success and contain a JSON object containing info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function editProfile(firstName:String, 
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
			
			if (!isNaN(lat) && !isNaN(lon) && isInvalidLocation(lat,lon))
				response = new Response(false, "Invalid location.");			
			if (email != null) 
			{
				email = StringUtil.trim(email).toLowerCase();
				if (isInvalidEmail(email))
					response = new Response(false, "Invalid email.");			
			}	
			if (city != null)
			{
				city = toTitleCase(StringUtil.trim(city));
				if(isInvalidCity(city))
					response = new Response(false, "Invalid city.");			
			}
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
			request.data = body;
			
			// Load request and callback.
			loadRequest(request, callback, onSuccess);
			
			// Handle events.
			function onSuccess(data:Object):void {
				// Save user data
				if (email != null) 		ServerAccess.email = email;
				if (password != null) 	ServerAccess.password = password;
			}
		}
		
		/**
		 * Attempts to add a score and review from you to the user with the given userId 
		 * regarding the given trade.  The score must be from 0 to 5.
		 * Requires that authenticate() have been called at least once.
		 * 
		 * 	userId:		The user's id to add the review to
		 *  tradeId:	The trade the review is in regards to
		 * 	score:		The score to give the user
		 * 	message:	The message body of the review
		 * 	callback: 	The function to call when the attempt is complete
		 *   
		 * The 'callback' function will be called and passed a 'Response' object as its argument. 
		 * SUCCESS: Response will indicate success and contain a JSON object containing info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function addReview(userId:String, 
										 tradeId:String, 
										 score:Number,
										 message:String,
										 callback:Function):void 
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if(userId == null || userId.length == 0)
				response = new Response(false, "Invalid user ID.");		
			if(tradeId == null || tradeId.length == 0)
				response = new Response(false, "Invalid trade ID.");	
			if(isNaN(score) || score < 0 || score > 5)
				response = new Response(false, "Invalid score (must be 0-5).");
			if(message == null || message.length == 0)
				response = new Response(false, "Invalid message.");			

			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
						
			// Construct JSON body
			var bodyObject:Object = {
				score:score,
				message:message
			};
			var body:String = JSON.stringify(bodyObject);
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/users/"+userId+"/trades/"+tradeId+"/reviews");
			addAuthenticationHeader(request, null, null); // Assume cached info exists.
			request.data = body;
			
			// Load request and callback.
			loadRequest(request, callback);
		}
		
		/**
		 * Attempts to add a resource for the currently authenticated user.
		 * Requires that authenticate() have been called at least once.
		 * 
		 * 	type:		The type of resource
		 * 	lat: 		The latitude of the user
		 * 	lon: 		The longitude of the user
		 * 	title:		The title of the resource
		 * 	description:The description of the resource
		 * 	points:		The number of points to award 
		 * 	callback: 	The function to call when the attempt is complete
		 *   
		 * The 'callback' function will be called and passed a 'Response' object as its argument. 
		 * SUCCESS: Response will indicate success and contain a JSON object containing info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function addResource(type:String, 
										   lat:Number,
										   lon:Number,
										   title:String,
										   description:String,
										   points:Number,
										   callback:Function):void 
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
				
			if (type == null || type.length == 0)
				response = new Response(false, "Invalid type.");	
			if (isInvalidLocation(lat,lon))	response = new Response(false, "Invalid location.");
			if (description == null || description.length == 0)
				response = new Response(false, "Invalid description.");	
			if (title == null || title.length == 0)
				response = new Response(false, "Invalid title.");
			if (description == null || description.length == 0)
				response = new Response(false, "Invalid description.");
			if (isNaN(points))
				response = new Response(false, "Invalid point amount.");
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Construct JSON body
			var bodyObject:Object = {
				type:type,
				location:{
					lat:lat, 
					lon:lon
				},
				title:title,
				description:description,
				points:points
			};
			var body:String = JSON.stringify(bodyObject);
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/users/"+userId+"/addResource");
			addAuthenticationHeader(request, null, null);
			request.data = body;
			
			// Load request and callback.
			loadRequest(request, callback);
		}
	
		/**
		 * Attempts to get a resource by its resource id.
		 * Requires that authenticate() have been called at least once.
		 * 
		 * 	resourceId:	The id of the resource to get
		 * 	callback: 	The function to call when the attempt is complete
		 *   
		 * The 'callback' function will be called and passed a 'Response' object as its argument. 
		 * SUCCESS: Response will indicate success and contain a JSON object containing info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function getResource(resourceId:String,
										   callback:Function):void 
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if (resourceId == null || resourceId.length == 0)
				response = new Response(false, "Invalid resource Id.");	
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/getResource/"+resourceId);
			addAuthenticationHeader(request, null, null);
			
			// Load request and callback.
			loadRequest(request, callback);
		}
		
		/**
		 * Attempts to get all resources for a given user id.
		 * Requires that authenticate() have been called at least once.
		 * 
		 * 	userId:		The id of the user to get the resources of
		 * 	callback: 	The function to call when the attempt is complete
		 *   
		 * The 'callback' function will be called and passed a 'Response' object as its argument. 
		 * SUCCESS: Response will indicate success and contain a JSON object containing info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function getResources(userId:String,
										    callback:Function):void 
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if (userId == null || userId.length == 0)
				response = new Response(false, "Invalid resource Id.");	
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/users/"+userId+"/getResources");
			addAuthenticationHeader(request, null, null);
			
			// Load request and callback.
			loadRequest(request, callback);
		}
		
		/**
		 * Attempts to get all resources within a given radius of a given set of coordinates.
		 * May optionally be filtered by type or search term.
		 * Requires that authenticate() have been called at least once.
		 * 
		 * 	lat: 			The latitude of the coordinates
		 * 	lon: 			The longitude of the coordinates
		 * 	radius:			The radius with which to search resources around the coordinates
		 * 	filterTypes:	[Optional] An array of strings containing valid resource types to 
		 * 					retrieve. Pass null to not filter by type.
		 * 	searchTerm:		[Optional] A search string to search titles by.
		 * 	callback: 		The function to call when the attempt is complete
		 *   
		 * The 'callback' function will be called and passed a 'Response' object as its argument. 
		 * SUCCESS: Response will indicate success and contain a JSON object containing info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function getResourceLocations(lat:Number,
													lon:Number,
													radius:int,
													filterTypes:Array = null,
													searchTerm:String = null,
													callback:Function = null):void 
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if (isInvalidLocation(lat,lon))	response = new Response(false, "Invalid location.");
			if (isNaN(radius))				response = new Response(false, "Invalid radius.");
			if (filterTypes != null && filterTypes.length >= 0 && !filterTypes[0] is String)
				response = new Response(false, "Invalid filter type (must be array of strings).");	
			if (searchTerm != null && searchTerm.length == 0)
				response = new Response(false, "Invalid search term.");	
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Create URL variables -- this allows our fields to be placed as objects and then 
			// sexily placed in our request's data.
			// However, since we're doing a POST, we have to manually toString() it and put it onto
			// the end of the url.
			var vars:URLVariables = new URLVariables();
			vars.lat = lat;
			vars.lon = lon;
			vars.radius = radius;
			if (filterTypes != null) 
				vars.filter = filterTypes;
			if (searchTerm != null)
				vars.searchterm = searchTerm;
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/getResourceLocations?"+vars.toString());
			addAuthenticationHeader(request, null, null);
			request.contentType = "application/x-www-form-urlencoded";
			
			// Load request and callback.
			loadRequest(request, callback);
		}
		
		/**
		 * Attempts to edit a resource for the currently authenticated user.
		 * Requires that authenticate() have been called at least once.
		 * 
		 * 	resourceId:	The id of the resource to edit
		 * 	callback: 	The function to call when the attempt is complete
		 * 
		 * Optional parameters to update: (Use 'null' if you don't want these to change, or NaN
		 * 								   for lat / lon)		
		 * 	type:		The type of resource
		 * 	lat: 		The latitude of the user
		 * 	lon: 		The longitude of the user
		 * 	title:		The title of the resource
		 * 	description:The description of the resource
		 * 	points:		The number of points to award 
		 *   
		 * The 'callback' function will be called and passed a 'Response' object as its argument. 
		 * SUCCESS: Response will indicate success and contain a JSON object containing info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function editResource(resourceId:String,
											type:String, 
										    lat:Number,
										    lon:Number,
										    title:String,
										    description:String,
										    points:Number,
										    callback:Function):void 
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if (resourceId == null || resourceId.length == 0)
				response = new Response(false, "Invalid resource Id.");	
			if (type != null && type.length == 0)
				response = new Response(false, "Invalid type.");	
			if (!isNaN(lat) && !isNaN(lon) && isInvalidLocation(lat,lon))
				response = new Response(false, "Invalid location.");		
			if (description != null && description.length == 0)
				response = new Response(false, "Invalid description.");	
			if (title != null && title.length == 0)
				response = new Response(false, "Invalid title.");
			if (description != null && description.length == 0)
				response = new Response(false, "Invalid description.");
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Construct JSON body
			var bodyObject:Object = new Object();
			if (type != null)			bodyObject["type"] = type;
			if (!isNaN(lat) && !isNaN(lon))				
										bodyObject["location"] = { lat:lat, lon:lon };
			if (title != null)			bodyObject["title"] = title;
			if (description != null)	bodyObject["description"] = description;
			if (!isNaN(points))			bodyObject["points"] = points;
			var body:String = JSON.stringify(bodyObject);
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/updateResource/"+resourceId);
			addAuthenticationHeader(request, null, null);
			request.data = body;
			
			// Load request and callback.
			loadRequest(request, callback);
		}
		
		/**
		 * Attempts to delete a resource by its resource id.
		 * Requires that authenticate() have been called at least once.
		 * 
		 * 	resourceId:	The id of the resource to delete
		 * 	callback: 	The function to call when the attempt is complete
		 *   
		 * The 'callback' function will be called and passed a 'Response' object as its argument. 
		 * SUCCESS: Response will indicate success and contain a JSON object containing info.
		 * FAILURE: Response will indicate failure and contain a message with the problem.
		 */
		public static function deleteResource(resourceId:String,
											  callback:Function):void 
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if (resourceId == null || resourceId.length == 0)
				response = new Response(false, "Invalid resource Id.");	
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/deleteResource/"+resourceId);
			addAuthenticationHeader(request, null, null);
			
			// Load request and callback.
			loadRequest(request, callback);
		}
	}
}