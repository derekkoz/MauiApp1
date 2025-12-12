using System;
using System.Collections.Generic;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Extensions.Sql;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace AzureSQL.ToDo;

public static class ToDoTrigger
{
    [Function("sql_trigger_todo")]
    public static void Run(
        [SqlTrigger("dbo.ToDo", "AZURE_SQL_CONNECTION_STRING_KEY")]
        IReadOnlyList<JsonElement> items,
        FunctionContext context)
    {
        var logger = context.GetLogger("ToDoTrigger");

        var connStr = Environment.GetEnvironmentVariable("AZURE_SQL_CONNECTION_STRING_KEY");
        if (string.IsNullOrWhiteSpace(connStr))
        {
            logger.LogError("Connection string 'AZURE_SQL_CONNECTION_STRING_KEY' is not set.");
            return;
        }

        try
        {
            using var conn = new SqlConnection(connStr);
            conn.Open();

            foreach (var element in items)
            {
                logger.LogInformation($"Raw item payload: {JsonSerializer.Serialize(element)}");

                Guid id = Guid.Empty;
                string? title = null;

                // handle top-level Id/id, nested Item.* and other common wrappers
                if (TryGetGuidProperty(element, "Id", out id) ||
                    TryGetGuidProperty(element, "id", out id) ||
                    TryGetGuidPropertyFromNested(element, "Item", "id", out id) ||
                    TryGetGuidPropertyFromNested(element, "Item", "Id", out id) ||
                    TryGetGuidPropertyFromNested(element, "data", "Id", out id) ||
                    TryGetGuidPropertyFromNested(element, "row", "Id", out id) ||
                    TryGetGuidPropertyFromNested(element, "Row", "Id", out id))
                {
                    TryGetStringProperty(element, "title", out title);
                    TryGetStringProperty(element, "Title", out title);

                    if (id == Guid.Empty)
                    {
                        logger.LogWarning("Extracted Id is empty; skipping.");
                        continue;
                    }

                    // Skipping logic for non-insert operations
                    if (element.TryGetProperty("Operation", out var op) && op.ValueKind == JsonValueKind.Number)
                    {
                        var opVal = op.GetInt32();
                        // 0 == insert, 1 == update; only process inserts
                        if (opVal != 0)
                        {
                            logger.LogDebug($"Skipping operation {opVal}");
                            continue;
                        }
                    }

                    // check Item.completed (boolean) to avoid marking already-completed rows
                    if (TryGetBoolPropertyFromNested(element, "Item", "completed", out var completed) && completed)
                    {
                        logger.LogDebug("Item already completed; skipping");
                        continue;
                    }

                    using var cmd = conn.CreateCommand();
                    cmd.CommandText = "UPDATE dbo.ToDo SET completed = 1 WHERE Id = @Id";
                    cmd.Parameters.AddWithValue("@Id", id);
                    var rows = cmd.ExecuteNonQuery();
                    logger.LogInformation($"Marked completed for Id={id}, rowsAffected={rows}, title={title}");
                }
                else
                {
                    logger.LogWarning("Could not extract Id from SQL trigger payload; skipping item.");
                }
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error processing SQL trigger items.");
        }
    }

    private static bool TryGetGuidProperty(JsonElement e, string propName, out Guid value)
    {
        value = Guid.Empty;
        if (e.ValueKind != JsonValueKind.Object) return false;
        if (!e.TryGetProperty(propName, out var prop)) return false;

        if (prop.ValueKind == JsonValueKind.String && Guid.TryParse(prop.GetString(), out var g))
        {
            value = g;
            return true;
        }

        return false;
    }

    private static bool TryGetGuidPropertyFromNested(JsonElement e, string outer, string inner, out Guid value)
    {
        value = Guid.Empty;
        if (e.ValueKind != JsonValueKind.Object) return false;
        if (!e.TryGetProperty(outer, out var nested)) return false;
        if (nested.ValueKind == JsonValueKind.Object)
        {
            return TryGetGuidProperty(nested, inner, out value);
        }
        // sometimes nested object is encoded as JSON string
        if (nested.ValueKind == JsonValueKind.String)
        {
            try
            {
                var parsed = JsonSerializer.Deserialize<JsonElement>(nested.GetString() ?? "");
                return TryGetGuidProperty(parsed, inner, out value);
            }
            catch { /* fallthrough */ }
        }
        return false;
    }

    private static bool TryGetBoolPropertyFromNested(JsonElement e, string outer, string inner, out bool value)
    {
        value = false;
        if (e.ValueKind != JsonValueKind.Object) return false;
        if (!e.TryGetProperty(outer, out var nested)) return false;

        // nested object case
        if (nested.ValueKind == JsonValueKind.Object)
        {
            if (nested.TryGetProperty(inner, out var prop))
            {
                if (prop.ValueKind == JsonValueKind.True) { value = true; return true; }
                if (prop.ValueKind == JsonValueKind.False) { value = false; return true; }
                if (prop.ValueKind == JsonValueKind.String && bool.TryParse(prop.GetString(), out var b)) { value = b; return true; }
            }
            return false;
        }

        // nested JSON string case
        if (nested.ValueKind == JsonValueKind.String)
        {
            try
            {
                var parsed = JsonSerializer.Deserialize<JsonElement>(nested.GetString() ?? "");
                if (parsed.ValueKind == JsonValueKind.Object && parsed.TryGetProperty(inner, out var prop))
                {
                    if (prop.ValueKind == JsonValueKind.True) { value = true; return true; }
                    if (prop.ValueKind == JsonValueKind.False) { value = false; return true; }
                    if (prop.ValueKind == JsonValueKind.String && bool.TryParse(prop.GetString(), out var b)) { value = b; return true; }
                }
            }
            catch { }
        }

        return false;
    }

    private static bool TryGetStringProperty(JsonElement e, string propName, out string? value)
    {
        value = null;
        if (e.ValueKind != JsonValueKind.Object) return false;
        if (!e.TryGetProperty(propName, out var prop)) return false;
        if (prop.ValueKind == JsonValueKind.String)
        {
            value = prop.GetString();
            return true;
        }
        return false;
    }
}
