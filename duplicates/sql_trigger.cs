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
    [Function("sql_trigger_todo")]
    public static async Task Run(
        [SqlTrigger("[dbo].[ToDo]", "AZURE_SQL_CONNECTION_STRING_KEY")]
            IReadOnlyList<SqlChange<ToDoItem>> changes,
        FunctionContext context
    )
    {
        var logger = context.GetLogger("ToDoTrigger");

        var connStr = Environment.GetEnvironmentVariable("AZURE_SQL_CONNECTION_STRING_KEY");
        if (string.IsNullOrWhiteSpace(connStr))
        {
            logger.LogError("Connection string 'AZURE_SQL_CONNECTION_STRING_KEY' is not set.");
            return;
        }

        await using var conn = new SqlConnection(connStr);
        try
        {
            await conn.OpenAsync();
        }
        catch (Exception ex)
        {
            logger.LogError($"Failed to open SQL connection: {ex}");
            return;
        }

        const string selectSql = "SELECT completed FROM dbo.ToDo WHERE id = @id;";
        const string updateSql = "UPDATE dbo.ToDo SET completed = @completed WHERE id = @id;";

        foreach (SqlChange<ToDoItem> change in changes)
        {
            ToDoItem toDoItem = change.Item;

            // Use the strongly-typed SqlChangeOperation instead of a null-conditional string conversion.
            var op = change.Operation;
            logger.LogInformation($"Change operation: {op}");
            logger.LogInformation($"Id: {toDoItem.Id}, Title: {toDoItem.title}, Url: {toDoItem.url}, Completed: {toDoItem.completed}");

            // Only process Inserts (avoid update loop). If you want other behavior, adjust here.
            if (op != SqlChangeOperation.Insert)
            {
                logger.LogInformation($"Skipping non-insert operation ({op}) for id={toDoItem.Id}.");
                continue;
            }

            // For new rows we want to mark them completed (change this rule if needed)
            bool completedValue = true;

            try
            {
                // read current stored value
                await using (var selCmd = conn.CreateCommand())
                {
                    selCmd.CommandText = selectSql;
                    selCmd.CommandType = CommandType.Text;
                    selCmd.Parameters.Add(new SqlParameter("@id", SqlDbType.UniqueIdentifier) { Value = toDoItem.Id });
                    var currentObj = await selCmd.ExecuteScalarAsync();
                    bool? currentCompleted = currentObj == null || currentObj is DBNull ? null : (bool?)Convert.ToBoolean(currentObj);

                    if (currentCompleted.HasValue && currentCompleted.Value == completedValue)
                    {
                        logger.LogInformation($"Skipping update for id={toDoItem.Id}: database value already completed={currentCompleted.Value}.");
                        continue;
                    }
                }

                // perform update only when different
                await using var cmd = conn.CreateCommand();
                cmd.CommandText = updateSql;
                cmd.CommandType = CommandType.Text;
                cmd.CommandTimeout = 60;
                cmd.Parameters.Add(new SqlParameter("@id", SqlDbType.UniqueIdentifier) { Value = toDoItem.Id });
                cmd.Parameters.Add(new SqlParameter("@completed", SqlDbType.Bit) { Value = completedValue });

                var rows = await cmd.ExecuteNonQueryAsync();
                if (rows > 0)
                {
                    logger.LogInformation($"Updated ToDo id={toDoItem.Id} set completed={completedValue} (rows={rows}).");
                }
                else
                {
                    logger.LogWarning($"No rows updated for ToDo id={toDoItem.Id}.");
                }
            }
            catch (Exception ex)
            {
                logger.LogError($"Error processing ToDo id={toDoItem.Id}: {ex}");
            }
        }
    }
}
