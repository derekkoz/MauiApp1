using System;
using System.Data;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using Xunit;

namespace Integration.Functions.Tests;

public class ToDoIntegrationTests
{
    private static string GetConn() =>
        Environment.GetEnvironmentVariable("AZURE_SQL_CONNECTION_STRING_KEY")
        ?? throw new InvalidOperationException("Set AZURE_SQL_CONNECTION_STRING_KEY environment variable to the DB connection string used by the Functions host.");

    [Fact]
    public async Task InsertRow_FunctionShouldMarkCompletedTrue()
    {
        var connStr = GetConn();

        var id = Guid.NewGuid();
        const string insertSql = "INSERT INTO dbo.ToDo (id, title, url, completed) VALUES (@id, @title, @url, 0);";
        const string selectSql = "SELECT completed FROM dbo.ToDo WHERE id = @id;";

        await using (var conn = new SqlConnection(connStr))
        {
            await conn.OpenAsync();

            await using (var cmd = conn.CreateCommand())
            {
                cmd.CommandText = insertSql;
                cmd.Parameters.Add(new SqlParameter("@id", SqlDbType.UniqueIdentifier) { Value = id });
                cmd.Parameters.Add(new SqlParameter("@title", SqlDbType.NVarChar, 200) { Value = "integration-test" });
                cmd.Parameters.Add(new SqlParameter("@url", SqlDbType.NVarChar, 500) { Value = "http://example/" });
                await cmd.ExecuteNonQueryAsync();
            }
        }

        // Poll until the function updates the row (timeout 30s)
        var succeeded = false;
        var deadline = DateTime.UtcNow.AddSeconds(30);
        while (DateTime.UtcNow < deadline)
        {
            await using var conn = new SqlConnection(connStr);
            await conn.OpenAsync();

            await using var cmd = conn.CreateCommand();
            cmd.CommandText = selectSql;
            cmd.Parameters.Add(new SqlParameter("@id", SqlDbType.UniqueIdentifier) { Value = id });

            var result = await cmd.ExecuteScalarAsync();
            if (result != null && result != DBNull.Value && Convert.ToBoolean(result))
            {
                succeeded = true;
                break;
            }

            await Task.Delay(1000);
        }

        Assert.True(succeeded, "Function did not mark the inserted ToDo row as completed within the timeout period.");
    }
}