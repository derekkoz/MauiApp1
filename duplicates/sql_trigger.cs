using System;
using System.Collections.Generic;
using System.Data;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Extensions.Sql;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace AzureSQL.ToDo;

public static class ToDoTrigger
{
    // TEMPORARY: disable SQL trigger registration while debugging host restarts.
    // To re-enable, uncomment the next line.
    // [Function("sql_trigger_todo")]
    public static void Run(
        [SqlTrigger("dbo.ToDo", ConnectionStringSetting = "AZURE_SQL_CONNECTION_STRING_KEY")] 
        IReadOnlyList<string> items,
        FunctionContext context)
    {
        var logger = context.GetLogger("ToDoTrigger");

        var connStr = Environment.GetEnvironmentVariable("AZURE_SQL_CONNECTION_STRING_KEY");
        if (string.IsNullOrWhiteSpace(connStr))
        {
            logger.LogError("Connection string 'AZURE_SQL_CONNECTION_STRING_KEY' is not set.");
            return;
        }

        using var conn = new SqlConnection(connStr);
        try
        {
            conn.Open();
        }
        catch (Exception ex)
        {
            logger.LogError($"Failed to open SQL connection: {ex}");
            return;
        }

        foreach (var item in items)
        {
            // Here you would process each item.
            // Since the items are strings, you might want to deserialize them
            // or handle them according to your application's logic.

            logger.LogInformation($"Received item: {item}");

            // For demonstration, let's just log the item.
            // Implement your logic here.
        }   

        // any az_func objects?
        logger.LogInformation($"-- any az_func objects?");
        using (var cmd = new SqlCommand("SELECT s.name AS SchemaName FROM sys.schemas s WHERE s.name = 'az_func';", conn))
        using (var reader = cmd.ExecuteReader())
        {
            while (reader.Read())
            {
                logger.LogInformation($"SchemaName: {reader.GetString(0)}");
            }
        }
        
        // list az_func tables
        logger.LogInformation($"-- list az_func tables");
        using (var cmd = new SqlCommand("SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'az_func';", conn))
        using (var reader = cmd.ExecuteReader())
        {
            while (reader.Read())
            {
                logger.LogInformation($"TABLE_SCHEMA: {reader.GetString(0)}, TABLE_NAME: {reader.GetString(1)}");
            }
        }
    }
}

/*
SQL queries referenced for manual inspection / run in your DB tool (Azure Data Studio / Query editor):

-- is change tracking enabled for DB?
SELECT databasepropertyex(DB_NAME(), 'IsChangeTrackingOn') AS ChangeTrackingOn;

-- is change tracking enabled on the table?
SELECT OBJECTPROPERTY(OBJECT_ID('dbo.ToDo'), 'TableHasChangeTracking') AS TableHasChangeTracking;

Place these queries into your SQL editor when you want to inspect DB change-tracking state.
*/
