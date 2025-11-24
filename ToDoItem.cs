using System.Text.Json.Serialization;

namespace AzureSQL.ToDo;

public class ToDoItem
{
    [JsonPropertyName("id")]
    public Guid Id { get; set; }
    public int? order { get; set; }
    public required string title { get; set; }
    public required string url { get; set; }
    public bool? completed { get; set; }
}

