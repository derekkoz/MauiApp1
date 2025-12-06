using System;
using System.Text.Json.Serialization;

namespace AzureSQL.ToDo;

public class ToDoItem
{
    [JsonPropertyName("id")]
    public Guid Id { get; set; }

    [JsonPropertyName("order")]
    public int? order { get; set; }

    [JsonPropertyName("title")]
    public string title { get; set; } = string.Empty;

    [JsonPropertyName("url")]
    public string url { get; set; } = string.Empty;

    [JsonPropertyName("completed")]
    public bool? completed { get; set; }
}

