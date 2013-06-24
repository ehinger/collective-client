package connectivity
{
	public class Response 
	{
		public static const TYPE_STRING:String = "TYPE_STRING";
		public static const TYPE_OBJECT:String = "TYPE_OBJECT";
		
		private var success:Boolean;
		private var type:String;
		private var data:Object;
		
		public function Response(success:Boolean, data:Object) 
		{
			this.success = success;
			this.data = data;
			
			// Set appropriate data type.
			if (data is String) 
			{
				type = TYPE_STRING;
			} 
			else
			{
				type = TYPE_OBJECT;
			}
		}
		public function isSuccess():Boolean {
			return success;			
		}
		public function getType():String {
			return type;			
		}
		public function getData():Object {
			return data;			
		}
	}
}