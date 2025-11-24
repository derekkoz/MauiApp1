using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Extensions.Sql;
using Microsoft.Extensions.Logging;

namespace AzureSQL.ToDo;

public static class ToDoTrigger
{
    [Function("sql_trigger_todo")]
    public static void Run(
        [SqlTrigger("[dbo].[ToDo]", "AZURE_SQL_CONNECTION_STRING_KEY")]
            IReadOnlyList<SqlChange<ToDoItem>> changes,
        FunctionContext context
    )
    {
        var logger = context.GetLogger("ToDoTrigger");
        foreach (SqlChange<ToDoItem> change in changes)
        {
            ToDoItem toDoItem = change.Item;
            logger.LogInformation($"Change operation: {change.Operation}");
            logger.LogInformation(
                $"Id: {toDoItem.Id}, Title: {toDoItem.title}, Url: {toDoItem.url}, Completed: {toDoItem.completed}"
            );
        }
    }
}
