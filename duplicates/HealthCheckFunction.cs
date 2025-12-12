using System.Net;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace AzureSQL.ToDo
{
    // Ensure the original HealthCheckFunction class does not collide with other files.
    public class HealthCheckFunctionV1
    {
        [Function("health")] // original function name
        public async Task<HttpResponseData> RunHealthV1(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "health")] HttpRequestData req,
            FunctionContext context)
        {
            var response = req.CreateResponse(HttpStatusCode.OK);
            var payload = "Healthy";
            var bytes = Encoding.UTF8.GetBytes(payload);

            // Async write to avoid synchronous I/O
            await response.Body.WriteAsync(bytes.AsMemory(0, bytes.Length));

            response.Headers.Add("Content-Type", "text/plain; charset=utf-8");
            return response;
        }
    }
}