using System;
using System.Data;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace AzureSQL.ToDo;

public class SqlOutputBindingHttpTriggerCSharp
{
    private readonly ILogger _logger;

    public SqlOutputBindingHttpTriggerCSharp(ILoggerFactory loggerFactory)
    {
        _logger = loggerFactory.CreateLogger<SqlOutputBindingHttpTriggerCSharp>();
    }

    [Function("httptrigger-sql-output")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequestData req,
        FunctionContext context)
    {
        _logger.LogInformation("C# HTTP trigger (code-based SQL) processed a request.");

        // Read request body
        string json;
        using (var sr = new StreamReader(req.Body))
        {
            json = await sr.ReadToEndAsync();
        }

        ToDoItem? toDoItem;
        try
        {
            toDoItem = JsonSerializer.Deserialize<ToDoItem>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to deserialize request body.");
            var bad = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
            await bad.WriteStringAsync("Invalid JSON body.");
            return bad;
        }

        if (toDoItem is null)
        {
            var bad = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
            await bad.WriteStringAsync("Request body missing or invalid.");
            return bad;
        }

        var connString = Environment.GetEnvironmentVariable("AZURE_SQL_CONNECTION_STRING_KEY");
        if (string.IsNullOrEmpty(connString))
        {
            _logger.LogError("AZURE_SQL_CONNECTION_STRING_KEY is not configured.");
            var err = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            await err.WriteStringAsync("Database connection not configured.");
            return err;
        }

        try
        {
            await using var conn = new SqlConnection(connString);
            await conn.OpenAsync();

            await using var cmd = conn.CreateCommand();
            cmd.CommandType = CommandType.Text;
            cmd.CommandText = @"
INSERT INTO dbo.ToDo (Id, [order], title, url, completed)
VALUES (@Id, @Order, @Title, @Url, @Completed);
";

            // Map fields - match your table columns. Use DBNull for nulls.
            var id = toDoItem.Id != Guid.Empty ? toDoItem.Id : Guid.NewGuid();
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@Order", toDoItem.order.HasValue ? (object)toDoItem.order.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@Title", string.IsNullOrEmpty(toDoItem.title) ? (object)DBNull.Value : toDoItem.title);
            cmd.Parameters.AddWithValue("@Url", string.IsNullOrEmpty(toDoItem.url) ? (object)DBNull.Value : toDoItem.url);
            cmd.Parameters.AddWithValue("@Completed", toDoItem.completed.HasValue ? (object)toDoItem.completed.Value : DBNull.Value);

            await cmd.ExecuteNonQueryAsync();

            var created = req.CreateResponse(System.Net.HttpStatusCode.Created);
            created.Headers.Add("Content-Type", "application/json; charset=utf-8");
            await created.WriteStringAsync(JsonSerializer.Serialize(toDoItem));
            return created;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to write ToDo to database.");
            var internalErr = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            await internalErr.WriteStringAsync("Error writing to database.");
            return internalErr;
        }
    }
}
