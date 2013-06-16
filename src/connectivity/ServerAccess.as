package connectivity
{
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.events.HTTPStatusEvent;
	import flash.events.IOErrorEvent;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	import flash.net.URLRequestMethod;
	
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
		public static function toTitleCase( original:String ):String {
			var words:Array = original.split( " " );
			for (var i:int = 0; i < words.length; i++) {
				words[i] = toInitialCap( words[i] );
			}
			return ( words.join( " " ) );
		}

		public static function toInitialCap( original:String ):String {
			return original.charAt( 0 ).toUpperCase(  ) + original.substr( 1 ).toLowerCase(  );
		}  
	
		// ========================================================================================
		// PUBLIC FUNCTIONS FOR INTERACTION WITH SERVER
		// ========================================================================================

		/**
		 * Registers a user with the given info and logs them in.
		 */
		public static function register(firstName:String, lastName:String, lat:Number, lon:Number,
										lookingFor:String,
										address:String, city:String, postcode:String, email:String,
		         						password:String, picture:Object, callback:Function):void 
		{
			var response:Response;
			
			// Validation
			// Location:
			if (lat < -90 || lat > 90 || lon < -180 || lon > 180){
				trace("Invalid location.");
				response = new Response(false, "Invalid location.");
				callback(response);
				return;
			}
			
			// Email:
			email = StringUtil.trim(email).toLowerCase();
			if (!email.match(/^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,4}$/)){
				trace("Invalid email.");
				response = new Response(false, "Invalid email.");
				callback(response);
				return;
			}
			
			// City:			
			city = toTitleCase(StringUtil.trim(city));
			if(!city.match(/^[A-Za-z]{3,20}\ ?([A-Za-z]{3,20})?$/)){
				trace("Invalid city.");
				response = new Response(false, "Invalid city.");
				callback(response);
				return;
			}
			
			// Postcode:
			postcode = StringUtil.trim(postcode);
			if (!postcode.match(/^[1-9][0-9]{3}$/)){
				trace("Invalid postcode.");
				response = new Response(false, "Invalid postcode.");
				callback(response);
				return;
			}
			
			// Construct JSON body
			var bodyObject:Object = {
				firstName:firstName,
				lastName:lastName,
				location:{
					lat:lat, 
					lon:lon
				},
				lookingFor:lookingFor,
				address:address,
				city:city,
				postcode:postcode,
				email:email,
				password:password,
				picture:picture				
			};
			var body:String = JSON.stringify(bodyObject);
			
			// Construct URL request
			var request:URLRequest = new URLRequest(hostname + "/users");
			request.contentType = "application/json";
			request.method = URLRequestMethod.POST;
			request.data = body;
			
			// Load URL request
			var loader:URLLoader = new URLLoader();
			
			// Add listener functions for various URL events.  The two we care about:
			// Complete: when data is loaded (successfully!)			
			loader.addEventListener(Event.COMPLETE, completeHandler);
			// IOError: failure for some reason, including a bad status code.
			loader.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
			
			//loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, httpStatusHandler);
			
			try {
				// This loads the request asynchronously. Event functions will fire
				// as appropriate.
				loader.load(request);
			} catch (error:Error) {
				// The errors that can be thrown are not tied to the server's responses
				// but are rather things like out of memory, syntax errors, etc. so we
				// can consider these to be rare occurrences.
				trace("Unable to load requested document.");
			}
			
			// Called when data is loaded successfully.
			function completeHandler(event:Event):void {
				var loader:URLLoader = URLLoader(event.target);
				trace("register completeHandler: " + loader.data);
				// Convert data to JSON if possible
				var data:Object = loader.data;
				if (loader.data != null) {
					try {
						data = JSON.parse(loader.data);
					} catch (error:Error) {
						trace("Cannot convert data to JSON. Using data as-is.");
					}
				}
				
				// Callback function: pass response indicating success along with the data, if any.
				response = new Response(true, data);
				callback(response);
			}
			
			// Called when an error occurs.
			function ioErrorHandler(event:IOErrorEvent):void {				
				var loader:URLLoader = URLLoader(event.target);
				trace("register ioErrorHandler: " + event + ", data: " + loader.data);
				// Convert data to JSON if possible
				var data:Object = loader.data;
				if (loader.data != null) {
					try {
						data = JSON.parse(loader.data);
					} catch (error:Error) {
						trace("Cannot convert data to JSON. Using data as-is.");
						data = loader.data;
					}
				}
				
				// Callback function: pass response indicating failure along with the data, if any.
				response = new Response(false, data);
				callback(response);
			}
			
			function httpStatusHandler(event:HTTPStatusEvent):void {
				var loader:URLLoader = URLLoader(event.target);
				trace("httpStatusHandler: " + event + ", data: " + loader.data);
				// This event doesn't contain data.  But the ioErrorHandler event doesn't contain
				// the status code.  Sigh.
			}
		}
		
		/**
		 * Edits a user's profile.  Any non-null parameters will be updated.
		 */
		public static function editProfile(userId:String, firstName:String, lastName:String, lat:Number, lng:Number,
										address:String, city:String, phone:String, email:String,
										password:String, picture:Object):Boolean 
		{
			return false;
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
		 * Gets a user's profile with the given id.
		 */
		public static function getProfile(userId:String):Object
		{
			return false;
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