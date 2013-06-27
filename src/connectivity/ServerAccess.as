package connectivity
{
	import com.adobe.crypto.MD5;
	import com.adobe.images.JPGEncoder;
	import com.adobe.utils.DateUtil;
	import com.dynamicflash.util.Base64;
	import com.flexoop.utilities.dateutils.DateUtils;
	
	import flash.display.Bitmap;
	import flash.display.BitmapData;
	import flash.display.Loader;
	import flash.display.PixelSnapping;
	import flash.events.Event;
	import flash.events.HTTPStatusEvent;
	import flash.events.IOErrorEvent;
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
	import flash.geom.Matrix;
	import flash.geom.Point;
	import flash.geom.Rectangle;
	import flash.net.FileReference;
	import flash.net.URLLoader;
	import flash.net.URLLoaderDataFormat;
	import flash.net.URLRequest;
	import flash.net.URLRequestHeader;
	import flash.net.URLRequestMethod;
	import flash.net.URLVariables;
	import flash.utils.ByteArray;
	
	import mx.utils.StringUtil;
	
	import connectivity.Response;
	
	/**
	 * This class contains methods to wrap interactions with the server.
	 */
	public class ServerAccess
	{		
		// Debug mode?
		private static const DEBUG:Boolean = true;
		
		// URL to server
		public static const hostname:String = "https://nodejs-collective-server.herokuapp.com";
		
		// Actions
		public static const ACTION_ADD_MESSAGE:String 		= "add_message";
		public static const ACTION_ADD_REVIEW:String 		= "add_review";
		public static const ACTION_ACCEPT:String	 		= "accept";
		public static const ACTION_DECLINE:String 			= "decline";
		public static const ACTION_CANCEL:String 			= "cancel";
		public static const ACTION_MARK_AS_COMPLETE:String 	= "mark_as_complete";
		public static const ACTION_AGREE:String 			= "agree";
		public static const ACTION_DISAGREE:String 			= "disagree";
		
		// Resources
		public static const RESOURCE_TYPE_TOOLS:String 		= "tools";
		public static const RESOURCE_TYPE_LAND:String		= "land";
		public static const RESOURCE_TYPE_SERVICES:String 	= "services";
		public static const RESOURCE_TYPE_PLANTS:String 	= "plants";
		
		// Image resizing: all uploaded images are resized to these dimensions.
		private static const DESIRED_PROFILE_IMAGE_WIDTH:Number = 75.0;
		private static const DESIRED_PROFILE_IMAGE_HEIGHT:Number = 145.0;
		private static const DESIRED_RESOURCE_IMAGE_WIDTH:Number = 76.0;
		private static const DESIRED_RESOURCE_IMAGE_HEIGHT:Number = 77.0;
		
		// Caching
		private static var cacheProfileImageDir:File = null;
		private static var cacheResourceImageDir:File = null;
		private static var cacheTradeDir:File = null;
		private static var setUp:Boolean = false;
		private static var cacheMaxAgeWeeks:Number = 12;
		
		// Cached session info
		private static var userId:String;
		private static var email:String;
		private static var password:String;
		
		/**
		 * Constructor 
		 */
		public function ServerAccess()
		{
			throw new Error("This class cannot be instantiated.");
		}
		
		// ========================================================================================
		// INTERNAL FUNCTIONS
		// ========================================================================================
		
		/**
		 * Sets up caching directories and removes expired files.
		 */
		private static function setUpCaching(userId:String):void
		{
			trace("ServerAccess: Setting up cache for userId "+userId);
			
			// Define cache directories
			cacheProfileImageDir = File.applicationStorageDirectory.resolvePath("profiles/");
			cacheResourceImageDir = File.applicationStorageDirectory.resolvePath("resources/");
			cacheTradeDir = File.applicationStorageDirectory.resolvePath("users/"+userId+"/");

			// Create cache directories (nothing happens if they already exist)
			cacheProfileImageDir.createDirectory();
			cacheResourceImageDir.createDirectory();
			cacheTradeDir.createDirectory();
			
			// Delete old cache data
			var currentDate:Date = new Date();
			try {
				// Assemble list of cached files
				var files:Array = cacheProfileImageDir.getDirectoryListing()
								  .concat(cacheResourceImageDir.getDirectoryListing())
								  .concat(cacheTradeDir.getDirectoryListing());
				// Go through each file and delete them if they're past expiry date
				for each (var file:File in files)
				{
					if (DateUtils.dateDiff(DateUtils.WEEK,file.modificationDate, currentDate) 
						> cacheMaxAgeWeeks)
					{
						trace("Cache: Deleting old file "+file.nativePath);
						file.deleteFile();
					}
				}
			} catch (error:Error) {
				trace("Cache: Unable to delete old cached files");
			}
		}
		
		/**
		 * Gets the latest file modification date of all files in the given directory,
		 * or null if there are no files.
		 */
		private static function getFreshestCachedFileDate(dir:File):Date 
		{
			var latestDate:Date = null;
			for each (var file:File in dir.getDirectoryListing())
			{
				// Is the latest date behind the modification date?
				if (latestDate == null || 
					DateUtils.dateDiff(DateUtils.SECONDS,file.modificationDate, latestDate) < 0)
				{
					// All hail the new latest date
					latestDate = file.modificationDate;
				}
			}
			return latestDate;
		}
		
		/**
		 * Caches the given image in the given dir with the given filename.
		 */
		private static function cacheImage(image:Bitmap, dir:File, name:String):void
		{
			var file:File = dir.resolvePath(name+".jpg");
			var stream:FileStream = new FileStream();
			try {
				stream.open(file, FileMode.WRITE);
				
				// Encode as jpg
				var encoder:JPGEncoder = new JPGEncoder();		
				var bytes:ByteArray = encoder.encode(image.bitmapData);
				
				stream.writeBytes(bytes);
				stream.close();
			} catch (error:Error) {
				if (DEBUG) trace("Cache: Could not cache image");
			}
			if (DEBUG) trace("Cache: Cached image to "+file.nativePath);
		}
		
		/**
		 * Gets the image at the given dir under the given name, as a byte array.
		 */
		private static function getCachedImage(dir:File, name:String):ByteArray
		{
			var file:File = dir.resolvePath(name+".jpg");
			var stream:FileStream = new FileStream();
			var bytes:ByteArray = new ByteArray();
			try {
				stream.open(file, FileMode.READ);
				stream.readBytes(bytes);
				stream.close();
			} catch (error:Error) {
				if (DEBUG) trace("Cache: Cached image unavailable. "+error.message);
				return null;
			}
			return bytes;
		}
		
		/**
		 * Caches the given trade (as a JSON string) at the given location under the given name.
		 */
		private static function cacheTrade(trade:String, dir:File, name:String):void
		{
			var file:File = dir.resolvePath(name+".dat");
			var stream:FileStream = new FileStream();
			try {
				stream.open(file, FileMode.WRITE);
				stream.writeUTF(trade);
				stream.close();
			} catch (error:Error) {
				if (DEBUG) trace("Cache: Could not cache trade");
			}
			if (DEBUG) trace("Cache: Cached trade to "+file.nativePath);
		}
		
		/**
		 * Gets the cached trade (as a JSON string) with the given name, or null if doesn't exist.
		 */
		private static function getCachedTrade(dir:File, name:String):String
		{
			var file:File = dir.resolvePath(name+".dat");
			var stream:FileStream = new FileStream();
			var trade:String = null;
			try {
				stream.open(file, FileMode.READ);
				trade = stream.readUTF();
				stream.close();
			} catch (error:Error) {
				if (DEBUG) trace("Cache: Cached trade unavailable");
			}
			return trade;
		}
		
		/**
		 * Gets the all cached trades (as an array of JSON objects) in the given dir.
		 */
		private static function getCachedTrades(dir:File):Array
		{
			var trades:Array = new Array();
			var stream:FileStream = new FileStream();
			try {
				for each (var file:File in dir.getDirectoryListing())
				{
					stream.open(file, FileMode.READ);
					trades.push(convertAnyJSON(stream.readUTF()));
					stream.close();
				}
			} catch (error:Error) {
				if (DEBUG) trace("Cache: Cached trades unavailable");
				trades = new Array();
			}
			return trades;
		}
		
		/**
		 * Caches the given email as the last user email.
		 */
		private static function cacheEmail(email:String):void 
		{
			var file:File = File.applicationStorageDirectory.resolvePath("lastlogin.dat");
			var stream:FileStream = new FileStream();
			try {
				stream.open(file, FileMode.WRITE);
				stream.writeUTF(email);
				stream.close();
			} catch (error:Error) {
				if (DEBUG) trace("Cache: Could not cache last user email");
			}
			if (DEBUG) trace("Cache: Cached email "+email);
		}
		
		/**
		 * Gets the cached email from file, or null if it doesn't exist.
		 */
		private static function getCachedEmail():String
		{
			var file:File = File.applicationStorageDirectory.resolvePath("lastlogin.dat");
			var stream:FileStream = new FileStream();
			var email:String = null;
			try {
				stream.open(file, FileMode.READ);
				email = stream.readUTF();
				stream.close();
			} catch (error:Error) {
				if (DEBUG) trace("Cache: Last user email not available");
			}
			return email;
		}
		
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
		
		/**
		 * Adds an authentication header to the given request, as well as setting the request
		 * method to POST (required due to AS3 limitation) and setting its data to an empty
		 * json body "{}" (also due to AS3 limitation).
		 * 
		 * If email is null then it attempts to use cached settings, in which case the 
		 * authenticate() method MUST have already been run at least once to flesh out the cache.
		 */
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
			*/
			request.method = URLRequestMethod.POST;
			
			// Encode the email+password into a base64 string
			var header:String = Base64.encode(email+":"+password);
			
			// Include it in an Authorization header and attach it to the request. 
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
		 * to a JSON object tree if applicable.  
		 * 
		 * <p>It also allows for onSuccess and onFailure functions. These are given the loader as
		 * their sole argument and can optionally return a Response, which will be used in the 
		 * callback if present.
		 */
		private static function loadRequest(request:URLRequest,
											callback:Function, 
											onSuccess:Function = null, 
											onFailure:Function = null,
											binary:Boolean=false):void
		{
			var response:Response;
			
			// Construct URL loader 
			var loader:URLLoader = new URLLoader();
			loader.dataFormat = URLLoaderDataFormat.TEXT;
			loader.addEventListener(Event.COMPLETE, completeHandler);
			loader.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
			loader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, httpStatusHandler);
			if (binary)
				loader.dataFormat = URLLoaderDataFormat.BINARY;
			
			// Load the request
			try {
				// This loads the request asynchronously. Event functions will fire
				// as appropriate.
				if (DEBUG) trace("Loading request "+request.url);
				loader.load(request);
			} catch (error:Error) {
				// The errors that can be thrown are not tied to the server's responses
				// but are rather things like out of memory, syntax errors, etc. so we
				// can consider these to be rare occurrences.
				if (DEBUG) trace("Unable to load requested document.");
				response = new Response(false, "Internal Error!");
				callback(response);
				return;
			}

			// Called when data is loaded successfully.
			function completeHandler(event:Event):void {
				
				var loader:URLLoader = URLLoader(event.target);
				if (DEBUG) trace("completeHandler: " + loader.data);
				
				// Call onSuccess function
				if (onSuccess != null)
					response = onSuccess(loader);
				
				// Callback function: pass response indicating success along with the data, if any.
				if (callback != null)
				{
					if (response == null)
						response = new Response(true, convertAnyJSON(loader.data));
					callback(response);
				}
			}
			
			// Called when an error occurs for some reason, including a bad status code.
			// This event doesn't contain the status code for some messed up reason.
			function ioErrorHandler(event:IOErrorEvent):void {				
				var loader:URLLoader = URLLoader(event.target);
				if (DEBUG) trace("ioErrorHandler: " + event + ", data: " + loader.data);				
				
				// Call onFailure function
				if (onFailure != null)
					response = onFailure(loader);
				
				// Callback function: pass response indicating failure along with the data, if any.
				if (callback != null)
				{
					if (response == null)
						response = new Response(false, convertAnyJSON(loader.data));
					callback(response);
				}
			}
			
			function httpStatusHandler(event:HTTPStatusEvent):void {
				if (DEBUG) trace("HTTP Status code: " + event.status);
			}
		}
		
		/**
		 * Converts the given ByteArray to a Bitmap and passes it to the callback function
		 * when it's done.
		 */
		private static function convertToBitmap(data:ByteArray, callback:Function):void
		{
			// Create loader and start loading image
			var imageLoader:Loader = new Loader();
			imageLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, imageLoadedHandler);
			imageLoader.loadBytes(data);
			
			// This event is called when loading is done.
			function imageLoadedHandler(event:Event):void
			{
				// Image has now been loaded, create Bitmap from it
				var src:BitmapData = new BitmapData(event.target.content.width, event.target.content.height);
				src.draw(event.target.content);
				var image:Bitmap = new Bitmap(src);
				
				// Callback with image
				callback(image);
			}
		}
		
		/**
		 * Scales and/or crops the image to be at the desired width and height specified by
		 * DESIRED_IMAGE_WIDTH and DESIRED_IMAGE_HEIGHT, and returns the resulting image.
		 */
		private static function handleBitmapResizing(image:Bitmap):Bitmap
		{
			// Both dimensions too large: scale
			if (image.width > DESIRED_PROFILE_IMAGE_WIDTH && image.height > DESIRED_PROFILE_IMAGE_HEIGHT)
			{
				// Determine scale to use (go by the least drastic scale)
				var xScale:Number = DESIRED_PROFILE_IMAGE_WIDTH / image.width;
				var yScale:Number = DESIRED_PROFILE_IMAGE_HEIGHT / image.height;
				var scale:Number = Math.max(xScale, yScale);
				
				// Create scaling matrix
				var matrix:Matrix = new Matrix();
				matrix.scale(scale, scale);
				
				// Create a new bitmap data at that scale and morph the image to it
				var smallBMD:BitmapData = new BitmapData(image.width * scale, image.height * scale, true, 0x000000);
				smallBMD.draw(image.bitmapData, matrix, null, null, null, true);
				
				// Reassemble as bitmap
				image = new Bitmap(smallBMD, PixelSnapping.NEVER, true);
			}
			
			// Too wide? Cut sides
			if (image.width > DESIRED_PROFILE_IMAGE_WIDTH) 
			{
				var startXPoint:Point = new Point(image.width/2.0 - DESIRED_PROFILE_IMAGE_WIDTH/2.0, 0);
				var croppedX:BitmapData = 
					cropBitmapData(image.bitmapData, startXPoint, DESIRED_PROFILE_IMAGE_WIDTH, DESIRED_PROFILE_IMAGE_HEIGHT);
				image = new Bitmap(croppedX, PixelSnapping.NEVER, true);
			}
			
			// Too high? Cut top and bottom
			if (image.height > DESIRED_PROFILE_IMAGE_HEIGHT) 
			{
				var startYPoint:Point = new Point(0, image.height/2.0 - DESIRED_PROFILE_IMAGE_HEIGHT/2.0);
				var croppedY:BitmapData = 
					cropBitmapData(image.bitmapData, startYPoint, DESIRED_PROFILE_IMAGE_WIDTH, DESIRED_PROFILE_IMAGE_HEIGHT);
				image = new Bitmap(croppedY, PixelSnapping.NEVER, true);
			}
			return image;
		}
		
		/**
		 * Crops bitmap data.
		 * From: http://www.kirupa.com/forum/showthread.php?321055-crop-my-bitmap-data
		 */
		private static function cropBitmapData(sourceBitmapData:BitmapData, startPoint:Point, width:Number, height:Number):BitmapData
		{
			var croppedBD:BitmapData = new BitmapData(width, height);
			croppedBD.copyPixels(sourceBitmapData, new Rectangle(startPoint.x, startPoint.y, width, height), new Point(0, 0));
			return croppedBD.clone();
			croppedBD.dispose();
		}
				
		// ========================================================================================
		// PUBLIC FUNCTIONS FOR INTERACTION WITH SERVER
		// ========================================================================================

		/**
		 * Gets the current user's userId.
		 * Requires that authenticate() have been called at least once.
		 */
		public static function getUserId():String {
			if (DEBUG) trace("userId="+userId);
			if (userId == null)
				throw new Error("No current userId: call authenticate() first!");
			return userId;
		}
		
		/**
		 * Gets the email of the last person to log in, or "" if not available.
		 */
		public static function getLastUserEmail():String {
			var email:String = getCachedEmail();
			return email==null?"":email;
		}
		
		/**
		 * Attempts to register a user with the server.  
		 * 	@param	firstName 	The first name of the user
		 * 	@param	lastName 	The last name of the user
		 * 	@param	lat 		The latitude of the user
		 * 	@param	lon 		The longitude of the user
		 * 	@param	address		The address of the user minus city and postcode
		 * 	@param	city		The city of the user 
		 * 	@param	postcode	The postcode of the user 
		 * 	@param	email		The email of the user
		 * 	@param	password	The password of the user
		 * 	@param	callback	The function to call when the attempt is complete.
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
			function onSuccess(loader:URLLoader):Response {
				// Save the user id for this session
				ServerAccess.userId = convertAnyJSON(loader.data)._id;
				// Cache the email
				cacheEmail(email);
				return null;
			}
			function onFailure(data:Object):void {}
		}
		
		/**
		 * Attempts to authenticate the given email and password with the server.  If successful,
		 * the username and password will be stored and used with calls to other methods that
		 * require authentication.
		 * 
		 * 	@param	email 		The user's email, will be converted to lower case
		 * 	@param	password	The user's password 
		 * 	@param	callback	The function to call when the attempt is complete.
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
			function onSuccess(loader:URLLoader):Response {
				
				// Save the user id for this session
				var data:Object = convertAnyJSON(loader.data);
				ServerAccess.userId = data._id;
				ServerAccess.email = email;
				ServerAccess.password = password;
				
				// Set up caching for this ID
				setUpCaching(data._id);
				
				// Cache the email
				cacheEmail(email);
				
				return null;
			}
		}
		
		/**
		 * Attempts to get a user's profile from the server.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * @param userId	The user's id
		 * @param callback 	The function to call when the attempt is complete.
		 */
		public static function getProfile(userId:String, 
										  callback:Function):void
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if(userId == null || userId.length == 0)
				response = new Response(false, "Invalid user ID.");
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
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
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * <p>For optional parameters: Use 'null' or 'NaN' if you don't want these to change		
		 * 
		 * @param callback 	The function to call when the attempt is complete.
		 * @param firstName	[Optional] The first name of the user
		 * @param lastName 	[Optional] The last name of the user
		 * @param lat 		[Optional] The latitude of the user 
		 * @param lon 		[Optional] The longitude of the user 
		 * @param address	[Optional] The address of the user minus city and postcode
		 * @param city		[Optional] The city of the user 
		 * @param postcode	[Optional] The postcode of the user 
		 * @param password	[Optional] The password of the user
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
			function onSuccess(loader:URLLoader):Response {
				// Save user data
				if (email != null) 		ServerAccess.email = email;
				if (password != null) 	ServerAccess.password = password;
				return null;
			}
		}
		
		/**
		 * Attempts to add a score and review from you to the user with the given userId 
		 * regarding the given trade.  The score must be from 0 to 5.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * @param userId	The user's id to add the review to
		 * @param tradeId	The trade the review is in regards to
		 * @param score		The score to give the user
		 * @param message	The message body of the review
		 * @param callback 	The function to call when the attempt is complete
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
						
			// Create URL variables 
			var vars:URLVariables = new URLVariables();
			vars.action = ACTION_ADD_REVIEW;
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/performTradeAction/"+tradeId+"?"+vars.toString());
			addAuthenticationHeader(request, null, null);
						
			// Construct JSON body
			var bodyObject:Object = {
				score:score,
				message:message
			};
			request.data = JSON.stringify(bodyObject);
						
			// Load request and callback.
			loadRequest(request, callback);
		}
		
		/**
		 * Attempts to add a resource for the currently authenticated user.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * @param type			The type of resource - use ServerAccess.RESOURCE_TYPE_*
		 * @param lat 			The latitude of the user
		 * @param lon 			The longitude of the user
		 * @param title			The title of the resource
		 * @param description	The description of the resource
		 * @param points		The number of points to award 
		 * @param callback 		The function to call when the attempt is complete
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
				
			switch(type)
			{
				case RESOURCE_TYPE_LAND: break;
				case RESOURCE_TYPE_PLANTS: break;
				case RESOURCE_TYPE_SERVICES: break;
				case RESOURCE_TYPE_TOOLS: break;
				default: response = new Response(false, "Invalid type.");
			}
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
				new URLRequest(hostname+"/addResource");
			addAuthenticationHeader(request, null, null);
			request.data = body;
			
			// Load request and callback.
			loadRequest(request, callback);
		}
	
		/**
		 * Attempts to get a resource by its resource id.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * @param resourceId	The id of the resource to get
		 * @param callback 		The function to call when the attempt is complete
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
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * @param userId	The id of the user to get the resources of
		 * @param callback 	The function to call when the attempt is complete
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
				new URLRequest(hostname+"/getUsersResources/"+userId);
			addAuthenticationHeader(request, null, null);
			
			// Load request and callback.
			loadRequest(request, callback);
		}
		
		/**
		 * Attempts to get all resources within a given radius of a given set of coordinates.
		 * May optionally be filtered by type or search term.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * <p>For optional parameters: Use 'null' if you don't want these to change		
		 * 
		 * @param lat 			The latitude of the coordinates
		 * @param lon 			The longitude of the coordinates
		 * @param radius		The radius with which to search resources around the coordinates
		 * @param filterTypes	[Optional] An array of strings containing valid resource types to 
		 * 						retrieve - use ServerAccess.RESOURCE_TYPE_* as array entries
		 * @param searchTerm	[Optional] A search string to search titles by.
		 * @param callback 		The function to call when the attempt is complete
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
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * <p>For optional parameters: Use 'null' or 'NaN' if you don't want these to change		
		 * 
		 * @param resourceId:	The id of the resource to edit	
		 * @param type			[Optional] The type of resource  - use Serveraccess.RESOURCE_TYPE_*
		 * @param lat 			[Optional] The latitude of the user
		 * @param lon 			[Optional] The longitude of the user
		 * @param title			[Optional] The title of the resource
		 * @param description	[Optional] The description of the resource
		 * @param points		[Optional] The number of points to award 
		 * @param callback: 	The function to call when the attempt is complete
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
			if (type != null)
				switch (type)
				{
					case RESOURCE_TYPE_LAND: break;
					case RESOURCE_TYPE_PLANTS: break;
					case RESOURCE_TYPE_SERVICES: break;
					case RESOURCE_TYPE_TOOLS: break;
					default: response = new Response(false, "Invalid type.");
				}					
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
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * @param resourceId	The id of the resource to delete
		 * @param callback 		The function to call when the attempt is complete
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
		
		/**
		 * Attempts to request a resource on behalf of the current user.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * <p>The returned object tree will contain all information on the trade, if successeful.
		 * 
		 * @param resourceId	The id of the resource to request
		 * @param callback 		The function to call when the attempt is complete
		 */
		public static function addTrade(resourceId:String,
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
				new URLRequest(hostname+"/requestNewTrade/"+resourceId);
			addAuthenticationHeader(request, null, null);
			
			// Load request and callback.
			loadRequest(request, callback);
		}
		
		/**
		 * Attempts to add a message to a trade for the current user.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * @param tradeId	The id of the trade
		 * @param message	The message to add
		 * @param callback 	The function to call when the attempt is complete
		 */
		public static function addMessage(tradeId:String,
										  message:String,
										  callback:Function):void 
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if (tradeId == null || tradeId.length == 0)
				response = new Response(false, "Invalid trade Id.");	
			if (message == null || message.length == 0)
				response = new Response(false, "Invalid message.");
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Create URL variables 
			var vars:URLVariables = new URLVariables();
			vars.action = ACTION_ADD_MESSAGE;
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/performTradeAction/"+tradeId+"?"+vars.toString());
			addAuthenticationHeader(request, null, null);
			request.contentType = "application/json";
			
			// Construct JSON body
			var bodyObject:Object = {
				message:message
			};
			request.data = JSON.stringify(bodyObject);
			
			// Load request and callback.
			loadRequest(request, callback);
		}
		
		/**
		 * Attempts to perform an action on a trade.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * @param tradeId	The id of the trade
		 * @param action	The action to take - use Serveraccess.ACTION_*
		 * @param callback 	The function to call when the attempt is complete
		 */
		public static function actionTrade(tradeId:String,
										   action:String,
										   callback:Function):void 
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if (tradeId == null || tradeId.length == 0)
				response = new Response(false, "Invalid trade Id.");
			switch (action)
			{
				case ACTION_ACCEPT: break;
				case ACTION_DECLINE: break;
				case ACTION_AGREE: break;
				case ACTION_DISAGREE: break;
				case ACTION_MARK_AS_COMPLETE: break;
				case ACTION_CANCEL: break;
				default: response = new Response(false, "Invalid action.");
			}
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Create URL variables 
			var vars:URLVariables = new URLVariables();
			vars.action = action;
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/performTradeAction/"+tradeId+"?"+vars.toString());
			addAuthenticationHeader(request, null, null);
			
			// Load request and callback.
			loadRequest(request, callback);
		}
		
		/**
		 * Attempts to get a trade by its tradeid.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * <p>Should the connection fail for any reason, this method will try to get the trade
		 * from the cache. If there is no trade, this method will report failure in its response.
		 * 
		 * @param tradeId	The id of the trade
		 * @param callback 	The function to call when the attempt is complete
		 */
		public static function getTrade(tradeId:String,
										callback:Function):void 
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if (tradeId == null || tradeId.length == 0)
				response = new Response(false, "Invalid trade Id.");
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Get cached trade
			var cachedTradeString:String = getCachedTrade(cacheTradeDir, tradeId);
			var currVer:int;
			var cachedTrade:Object;
			if (cachedTradeString != null)
			{
				cachedTrade = convertAnyJSON(cachedTradeString);
				currVer = cachedTrade.version;
				if (DEBUG) trace("Cache: Trade found with version "+currVer);
			}
			
			// Create URL variables 
			var vars:URLVariables = new URLVariables();
			vars.currVer = currVer; //TODO cache
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/getTrade/"+tradeId
					+(cachedTradeString==null?"":"?"+vars.toString()));
			addAuthenticationHeader(request, null, null);
			request.contentType = "application/x-www-form-urlencoded";
			
			// Load request and callback.
			loadRequest(request, callback, onSuccess, onFailure);
			
			// Handle events.
			function onSuccess(loader:URLLoader):Response 
			{
				// Was a trade attached? Load it
				var json:Object = convertAnyJSON(loader.data);
				if (json.hasOwnProperty("_id"))
				{
					if (DEBUG) trace("Cache: New trade transmitted from server");
					// Write trade to cache
					cacheTrade(loader.data, cacheTradeDir, tradeId)
					return new Response(true, json);
				}
				// No trade attached, load cached trade	
				else if (cachedTrade != null)
				{
					if (DEBUG) trace("Cache: Cached trade up to date, using it");				
					return new Response(true, cachedTrade);
				} 
				// Impossibru error
				else 
				{
					return new Response(false, "Internal error that should be impossible!");
				}
			}
				
			function onFailure(loader:URLLoader):Response 
			{				
				// Cached data?  Use that.
				if (cachedTrade != null)
				{
					if (DEBUG) trace("Cache: Failed to connect to server, using cached trade");				
					return new Response(true, cachedTrade);
				} 
				// No cache: failure
				else
				{
					return null;
				}
			}
		}
		
		/**
		 * Attempts to get the trades belonging to the current user.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * <p>Should the connection fail for any reason, this method will try to get the trades 
		 * from the cache. If there are no trades, this method will report failure in its response.
		 * 
		 * @param callback 	The function to call when the attempt is complete
		 */
		public static function getTrades(callback:Function):void 
		{
			var response:Response;
						
			// --- REQUEST ------------------------------------------------------------------------
			
			// Create URL variables, get latest modified trade date and convert to ISO8601 format
			var latestDate:Date = getFreshestCachedFileDate(cacheTradeDir);
			var vars:URLVariables = new URLVariables();
			if (latestDate != null)	vars.date = DateUtil.toW3CDTF(latestDate);
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/getUsersTrades/"+userId
					+(latestDate==null?"":"?"+vars.toString()));
			addAuthenticationHeader(request, null, null);
			
			// Load request and callback.
			loadRequest(request, callback, onSuccess, onFailure);
			
			// Handle events.
			function onSuccess(loader:URLLoader):Response 
			{
				// Were any trades attached? 
				var json:Object = convertAnyJSON(loader.data);
				if (json.hasOwnProperty("length") && json.length > 0)
				{
					if (DEBUG) trace("Cache: New trades transmitted from server");
					
					// Cache each trade
					for each (var trade:Object in json)
					{
						var tradeAsString:String = JSON.stringify(trade);
						cacheTrade(tradeAsString, cacheTradeDir, trade._id)
					}
					
					// Get all cached trades for this user
					var allTrades:Array = getCachedTrades(cacheTradeDir);
					if (allTrades.length > 0) 
					{
						return new Response(true, allTrades);
					}					
					// No cached trades? This is possible if caching failed. Return the 
					// transmitted trades.
					else
					{
						return new Response(true, json);
					}
				}
				// No trade attached, load cached trades
				else 
				{
					if (DEBUG) trace("Cache: Cached trades up to date, using them");
					var cachedTrades:Array = getCachedTrades(cacheTradeDir);
					return new Response(true, cachedTrades);
				} 
			}
			
			function onFailure(loader:URLLoader):Response 
			{				
				// Cached data?  Use that.
				var cachedTrades:Array = getCachedTrades(cacheTradeDir);
				if (cachedTrades.length > 0)
				{
					if (DEBUG) trace("Cache: Failed to connect to server, using cached trade");				
					return new Response(true, cachedTrades);
				} 
				// No cache: failure
				else
				{
					return null;
				}
			}
		}
		
		/**
		 * Attempts to upload an image to the server as the current user's profile image, 
		 * scaling/cropping/converting it before transmitting.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * @param image		The bitmap image to upload
		 * @param callback 	The function to call when the attempt is complete
		 */
		public static function addProfileImage(image:Bitmap,
											   callback:Function):void
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if (image == null)
				response = new Response(false, "Invalid image.");
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Resize image
			image = handleBitmapResizing(image);

			// Convert image
			var encoder:JPGEncoder = new JPGEncoder();
			var data:ByteArray = encoder.encode(image.bitmapData);

			// Encode into base64 string
			var base64:String = Base64.encodeByteArray(data);
			
			// Get MD5
			var md5:String = MD5.hashBinary(data);
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/uploadProfileImage/"+userId);
			addAuthenticationHeader(request, null, null);
			
			// Construct JSON body
			var bodyObject:Object = {
				image:base64,
				hash:md5
			};
			request.data = JSON.stringify(bodyObject);
						
			// Load request then callback (binary data = true!)
			loadRequest(request, callback, onSuccess, null, true);
			
			// Handle events.
			function onSuccess(loader:URLLoader):Response {
				// Write image to cache
				cacheImage(image, cacheProfileImageDir, userId);
				return null;
			}
		}
		
		/**
		 * Attempts to upload an image to the server for the given resource id, 
		 * scaling/cropping/converting it before transmitting.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * @param image			The bitmap image to upload
		 * @param resourceId	The id of the resource to attach the picture to
		 * @param callback 		The function to call when the attempt is complete
		 */
		public static function addResourceImage(image:Bitmap,
												resourceId:String,
											    callback:Function):void
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if (image == null)
				response = new Response(false, "Invalid image.");
			if (resourceId == null || resourceId.length == 0)
				response = new Response(false, "Invalid resource Id.");	
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Resize image
			image = handleBitmapResizing(image);
			
			// Convert image
			var encoder:JPGEncoder = new JPGEncoder();
			var data:ByteArray = encoder.encode(image.bitmapData);
			
			// Encode into base64 string
			var base64:String = Base64.encodeByteArray(data);
			
			// Get MD5
			var md5:String = MD5.hashBinary(data);
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/addResourceImage/"+resourceId);
			addAuthenticationHeader(request, null, null);
			
			// Construct JSON body
			var bodyObject:Object = {
				image:base64,
				hash:md5
			};
			request.data = JSON.stringify(bodyObject);
			
			// Load request then callback (binary data = true!)
			loadRequest(request, callback, onSuccess, null, true);
			
			// Handle events.
			function onSuccess(loader:URLLoader):Response {
				// cache image
				cacheImage(image, cacheResourceImageDir, resourceId);
				return null;
			}
		}
		
		/**
		 * Attempts to retrieve a user's profile image.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * <p>Should the connection fail for any reason, this method will try to get the image 
		 * from the cache. If there is no image, this method will report failure in its response.
		 * 
		 * @param userId	The user's id
		 * @param callback 	The function to call when the attempt is complete
		 */
		public static function getProfileImage(userId:String,
											   callback:Function):void
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if (userId == null || userId.length == 0)
				response = new Response(false, "Invalid user id.");
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
						
			// Get cached image bytes			
			var bytes:ByteArray = getCachedImage(cacheProfileImageDir, userId);
			var usedCache:Boolean = false;
			var md5:String = null;
			
			// Not null: there is a cached image
			if (bytes != null) 
			{
				// Determine md5
				md5 = MD5.hashBinary(bytes);
				if (DEBUG) trace("Cache: Found existing image for userId="+userId);
			}
			
			// Create URL variables
			var vars:URLVariables = new URLVariables();
			if (md5 != null) vars.hash = md5;
						
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/getProfileImage/"+userId+"?"+vars.toString());
			addAuthenticationHeader(request, null, null);
			request.contentType = "application/x-www-form-urlencoded";

			// Construct URL loader 
			var loader:URLLoader = new URLLoader();
			loader.dataFormat = URLLoaderDataFormat.TEXT;
			loader.addEventListener(Event.COMPLETE, completeHandler);
			loader.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
			
			// Load the request
			try {
				if (DEBUG) trace("Loading request "+request.url);
				loader.load(request);
			} catch (error:Error) {
				if (DEBUG) trace("Unable to load requested document.");
				response = new Response(false, "Internal Error!");
				callback(response);
				return;
			}
			
			// Called when data is loaded successfully.
			function completeHandler(event:Event):void 
			{
				var loader:URLLoader = URLLoader(event.target);
				if (DEBUG) trace("completeHandler: " + loader.data);
				
				// Was an image attached?
				var json:Object = convertAnyJSON(loader.data);
				if (json.hasOwnProperty("image"))
				{
					if (DEBUG) trace("Cache: New image transmitted from server");
					// Encode base64 image string into bytearray.
					var data:ByteArray = Base64.decodeToByteArray(json.image);
					// Convert byte array to image
					usedCache = false;
					convertToBitmap(data, onImageLoaded);
				}
					// No image attached, load cached image	
				else if (bytes != null)
				{
					if (DEBUG) trace("Cache: Cached image up to date, using it");				
					usedCache = true;
					convertToBitmap(bytes, onImageLoaded);
				} 
					// Impossibru error
				else 
				{
					response = new Response(false, "Internal error that should be impossible!");
					callback(response);
				}
			}
			
			// Called when image has been converted from a byte array
			function onImageLoaded(image:Bitmap):void
			{
				// Cache it?
				if (!usedCache)
					cacheImage(image, cacheProfileImageDir, userId);
					
				// Callback with image 
				response = new Response(true, image);
				callback(response);
			}
			
			// Called when an error occurs for some reason, including a bad status code.
			function ioErrorHandler(event:IOErrorEvent):void 
			{				
				var loader:URLLoader = URLLoader(event.target);
				if (DEBUG) trace("ioErrorHandler: " + event + ", data: " + loader.data);
				
				// Cached data?  Use that.
				if (bytes != null)
				{
					if (DEBUG) trace("Cache: Failed to connect to server, using cached image");				
					usedCache = true;
					convertToBitmap(bytes, onImageLoaded);
				} 
				// No cache: failure
				else
				{
					response = new Response(false, convertAnyJSON(loader.data));
					callback(response);
				}
			}
		}
		
		/**
		 * Attempts to retrieve a resource's image.
		 * <br>Requires that authenticate() have been called at least once.
		 * 
		 * <p>Should the connection fail for any reason, this method will try to get the image 
		 * from the cache. If there is no image, this method will report failure in its response.
		 * 
		 * @param resourceId	The resource's id
		 * @param callback 		The function to call when the attempt is complete
		 */
		public static function getResourceImage(resourceId:String,
											    callback:Function):void
		{
			var response:Response;
			
			// --- VALIDATION --------------------------------------------------------------------- 
			
			if (resourceId == null || resourceId.length == 0)
				response = new Response(false, "Invalid resource id.");
			
			// Callback and abort if validation failed.
			if (response != null && !response.isSuccess()) {
				callback(response);
				return;
			}
			
			// --- REQUEST ------------------------------------------------------------------------
			
			// Get cached image bytes			
			var bytes:ByteArray = getCachedImage(cacheResourceImageDir, resourceId);
			var usedCache:Boolean = false;
			var md5:String = null;
			
			// Not null: there is a cached image
			if (bytes != null) 
			{
				// Determine md5
				md5 = MD5.hashBinary(bytes);
				if (DEBUG) trace("Cache: Found existing image for resourceId="+resourceId);
			}
			
			// If image in content, 
			//    use it
			//    cache it
			// If content blank,
			//    use cached image
			
			// Create URL variables
			var vars:URLVariables = new URLVariables();
			if (md5 != null) vars.hash = md5;
			
			// Construct URL request
			var request:URLRequest = 
				new URLRequest(hostname+"/getResourceImage/"+resourceId+"?"+vars.toString());
			addAuthenticationHeader(request, null, null);
			request.contentType = "application/x-www-form-urlencoded";
			
			// Construct URL loader 
			var loader:URLLoader = new URLLoader();
			loader.dataFormat = URLLoaderDataFormat.TEXT;
			loader.addEventListener(Event.COMPLETE, completeHandler);
			loader.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
			
			// Load the request
			try {
				if (DEBUG) trace("Loading request "+request.url);
				loader.load(request);
			} catch (error:Error) {
				if (DEBUG) trace("Unable to load requested document.");
				response = new Response(false, "Internal Error!");
				callback(response);
				return;
			}
			
			// Called when data is loaded successfully.
			function completeHandler(event:Event):void 
			{
				var loader:URLLoader = URLLoader(event.target);
				if (DEBUG) trace("completeHandler: " + loader.data);
				
				// Was an image attached?
				var json:Object = convertAnyJSON(loader.data);
				if (json.hasOwnProperty("image"))
				{
					if (DEBUG) trace("Cache: New image transmitted from server");
					// Encode base64 image string into bytearray.
					var data:ByteArray = Base64.decodeToByteArray(json.image);
					// Convert byte array to image
					usedCache = false;
					convertToBitmap(data, onImageLoaded);
				}
				// No image attached, load cached image	
				else if (bytes != null)
				{
					if (DEBUG) trace("Cache: Cached image up to date, using it");				
					usedCache = true;
					convertToBitmap(bytes, onImageLoaded);
				} 
				// Impossibru error
				else 
				{
					response = new Response(false, "Internal error that should be impossible!");
					callback(response);
				}
			}
			
			// Called when image has been converted from a byte array
			function onImageLoaded(image:Bitmap):void
			{
				// Cache it?
				if (!usedCache)
					cacheImage(image, cacheResourceImageDir, userId);
				
				// Callback with image 
				response = new Response(true, image);
				callback(response);
			}
			
			// Called when an error occurs for some reason, including a bad status code.
			function ioErrorHandler(event:IOErrorEvent):void 
			{				
				var loader:URLLoader = URLLoader(event.target);
				if (DEBUG) trace("ioErrorHandler: " + event + ", data: " + loader.data);
				
				// Cached data?  Use that.
				if (bytes != null)
				{
					if (DEBUG) trace("Cache: Failed to connect to server, using cached image");				
					usedCache = true;
					convertToBitmap(bytes, onImageLoaded);
				} 
					// No cache: failure
				else
				{
					response = new Response(false, convertAnyJSON(loader.data));
					callback(response);
				}
			}
		}
	}
}