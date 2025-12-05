using System.Net;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace AzureSQL.ToDo
{
    public class HealthCheckFunction
    {
        [Function("health")]
        public async Task<HttpResponseData> Run(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "health")] HttpRequestData req,
            FunctionContext context)
        {
            var response = req.CreateResponse(HttpStatusCode.OK);
            var payload = "Healthy";
            var bytes = Encoding.UTF8.GetBytes(payload);

            // Async write to avoid synchronous I/O (Kestrel disallows sync writes)
            await response.Body.WriteAsync(bytes.AsMemory(0, bytes.Length), CancellationToken.None);

            response.Headers.Add("Content-Type", "text/plain; charset=utf-8");
            return response;
        }
    }
}