using System;
using System.Threading.Tasks;
using Xunit;
using Microsoft.Data.SqlClient;

namespace Integration.Functions.Tests;

public class ToDoIntegrationTests
{
    [Fact]
    public async Task InsertRow_IsProcessedByFunction_CompletedBecomesTrue()
    {
        var connStr = Environment.GetEnvironmentVariable("AZURE_SQL_CONNECTION_STRING_KEY");
        Assert.False(string.IsNullOrWhiteSpace(connStr), "Set AZURE_SQL_CONNECTION_STRING_KEY environment variable to the DB connection string used by the Functions host.");

        var id = Guid.NewGuid();
        await using var conn = new SqlConnection(connStr);
        await conn.OpenAsync();

        // Insert a test row (completed = false)
        const string insertSql = "INSERT INTO dbo.ToDo (id, [order], title, url, completed) VALUES (@id, @order, @title, @url, @completed);";
        await using (var insertCmd = conn.CreateCommand())
        {
            insertCmd.CommandText = insertSql;
            insertCmd.Parameters.AddWithValue("@id", id);
            insertCmd.Parameters.AddWithValue("@order", 9999);
            insertCmd.Parameters.AddWithValue("@title", "it-test-trigger");
            insertCmd.Parameters.AddWithValue("@url", "https://example.test");
            insertCmd.Parameters.AddWithValue("@completed", false);
            await insertCmd.ExecuteNonQueryAsync();
        }

        // Poll until the function sets completed = true (timeout 15s)
        var processed = false;
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.Elapsed < TimeSpan.FromSeconds(15))
        {
            await using var checkCmd = conn.CreateCommand();
            checkCmd.CommandText = "SELECT completed FROM dbo.ToDo WHERE id = @id;";
            checkCmd.Parameters.AddWithValue("@id", id);
            var obj = await checkCmd.ExecuteScalarAsync();
            if (obj != null && obj != DBNull.Value && Convert.ToBoolean(obj))
            {
                processed = true;
                break;
            }
            await Task.Delay(500);
        }

        Assert.True(processed, "Function did not mark row completed within timeout.");

        // cleanup
        await using (var del = conn.CreateCommand())
        {
            del.CommandText = "DELETE FROM dbo.ToDo WHERE id = @id;";
            del.Parameters.AddWithValue("@id", id);
            await del.ExecuteNonQueryAsync();
        }
    }
}