package connectivity
{
	public class Response 
	{
		private var success:Boolean;
		private var data:Object;
		public function Response(success:Boolean, data:Object) 
		{
			this.success = success;
			this.data = data;
		}
		public function isSuccess():Boolean {
			return success;			
		}
		public function getData():Object {
			return data;			
		}
	}
}