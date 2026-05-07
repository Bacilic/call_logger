# Helpdesk API | Configuration

## API Keys

[![](../../images/plus.png) Add API key](/configuration/Api/ApiActions.aspx?action=addapikey "Add API key")

|  | Key Name | Key |  |  |  |
| --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |

## Documentation

### General

The helpdesk API can be used to get or alter helpdesk information by sending requests with certain parameters to the application.

Then the application will return data in JSON-Format. With this information you are able to build your own interface.

To use the API send your requests to the following URL:

URL : {scanserver}:{port}/api.aspx

The API won't return any data without an API key. So add the key as following:

URL : {scanserver}:{port}/api.aspx?key={key}

To select the wanted function append 'action' to the URL followed by the chosen function like this:

URL : {scanserver}:{port}/api.aspx?key={key}&action={function}

Functions will need parameters so also append the parameter names and values to the URL like this:

URL : {scanserver}:{port}/api.aspx?key={key}&action={function}&{parameter}={value}

Note: To add multiple parameters just add another '&' followed by the parameter name and value. Also don't use spaces but use '%20' instead.

### Function Overview

|  | Function | Description |
| --- | --- | --- |
| POST | [AddTicket](#AddTicketBookmark) | Create a new ticket to the system. |
| POST | [EditTicket](#EditTicketBookmark) | Edit an existing ticket. |
| GET | [GetTicket](#GetTicketBookmark) | Returns the requested ticket. |
| POST | [AddNote](#AddNoteBookmark) | Add a note(reply) to a ticket. |
| POST | [EditNote](#EditNoteBookmark) | Edit an existing reply. |
| GET | [GetNotes](#GetNotesBookmark) | Returns all the notes of a certain ticket. |
| POST | [AddAsset](#AddAssetBookmark) | If a ticket is about a certain asset you can add this to the ticket. |
| POST | [RemoveAsset](#RemoveAssetBookmark) | Remove an assigned asset again from a ticket. |
| GET | [GetAssets](#GetAssetsBookmark) | Returns all assets assigned to a ticket. |
| GET | [SearchTickets](#SearchTicketsBookmark) | Returns all ticket id's that match the search criteria. |
| GET | [SearchUsers](#SearchUsersBookmark) | Returns all users that match the search criteria. |
| POST | [EditTicketCustomField](#EditTicketCustomFieldBookmark) | Fill in or edit a custom field value for a ticket. |
| POST | [DeleteTicketCustomField](#DeleteTicketCustomFieldBookmark) | Clear a custom field value of a ticket. |

## Endpoints

### AddTicket

- Name: AddTicket
- Method: POST
- URL: /api.aspx?action=AddTicket&key={key}

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| Subject | String | True | The subject of the ticket. |
| Description | String | True | The description of the ticket. |
| Type | String | False | The ticket type. Standard types are : Hardware, Internet, Intranet, Network, Operating System, Sales, Services, Support. Other types can be added in the website. When no value given the standard type will be set to default. The default type can be changed on the helpdesk setup page. |
| Priority | String | False | The priority of a ticket. Standard priorities are : Low, Medium, High. Other priorities can be added in the website. When no value given the standard priority will be set to default. The default priority can be changed on the helpdesk setup page. |
| Team | String | False | The agent team you want your ticket send to. Standard teams are : Sales, Information Technology, Administration. Other team can be added in the website. |
| Username | String | False\* | The login username (domain\username) of the user who sends the ticket.     When no user is found the API will try to create a new one with an existing AD user based on the entered username and/or email. When no AD user is found the system will try to create a Non-AD user if you entered a displayname and email. If only the email is entered, the email is used as displayname. When none of these properties are given no user can be found or created and the ticket creation will fail. |
| Displayname | String | False | The displayname of the user who sends the ticket. The system will not search on displayname. However, it will use this when a new user is created.     When no user is found the API will try to create a new one with an existing AD user based on the entered username and/or email. When no AD user is found the system will try to create a Non-AD user if you entered a displayname and email. If only the email is entered, it is used as displayname. When none of these properties are given no user can be found or created and the ticket creation will fail. |
| Email | String | False\* | The email of the user who sends the ticket.     When no user is found the API will try to create a new one with an existing AD user based on the entered username and/or email. When no AD user is found the system will try to create a Non-AD user if you entered a displayname and email. If only the email is entered, it is used as displayname. When none of these properties are given no user can be found or created and the ticket creation will fail. |
| AgentUsername | String | False | The username (domain\username) of the agent to who the ticket is send to. |
| AgentEmail | String | False | The email of the agent to who the ticket is send to. |
| Date | DateTime | False | The creation date of the ticket. If not filled in the system will use the current time. The date should be formatted following the ISO 8601 standard. e.g. '2015-05-06T15:43:54' |
| AgentInitiated | Boolean | False | Is this ticket marked as initiated by an agent. |
| Personal | Boolean | False | Is this ticket marked as personal. Users will be allowed to see the agents name when a ticket is set to personal. |
| CustomFields | Object | False | A JSON-object containing the key-value pairs of the custom field(s). The object must be a valid JSON-object and must be URL-encoded.   Example with multiple custom fields:  [{"name":"textBoxCustomFieldExample","value":"Textbox custom field value here."},{"name":"datetimeCustomFieldExample","value":"2015-05-06T00:00:00"},{"name":"multiSelectCustomFieldExample","values":["a","b","c","d"]}]  URL-encoded version of this JSON-object:  %7B%22customFields%22%3A%5B%7B%22name%22%3A%22textBoxCustomFieldExample%22%2C%22value%22%3A%22Textbox%20custom%20field%20value%20here.%22%7D%2C%7B%22name%22%3A%22datetimeCustomFieldExample%22%2C%22value%22%3A%222015-05-06T00%3A00%3A00%22%7D%2C%7B%22name%22%3A%22multiSelectCustomFieldExample%22%2C%22values%22%3A%5B%22a%22%2C%22b%22%2C%22c%22%2C%22d%22%5D%7D%5D%7D  Example with only one custom field:  {"customFields":[{"name":"textBoxCustomFieldExample","value":"Textbox custom field value here."}]}  URL-encoded version of this JSON-object:  %7B%22customFields%22%3A%5B%7B%22name%22%3A%22textBoxCustomFieldExample%22%2C%22value%22%3A%22Textbox%20custom%20field%20value%20here.%22%7D%5D%7D  Note: When using multiselect you should use "values" instead of "value".     JSON-object properties:  |  |  | | --- | --- | | Name | The name of the custom field. | | Value | The value of the custom field. | | Values | The values of the custom field. (Only a multiselect custom field can contain multiple values). | |
| Files | File(s) | False | The files you want to add as attachment to a ticket.    Note that you can not add these as parameter of a URL and you'll need to use a script to generate a post containing the files. For more information on how to do this you can check the examples underneath. |
| \* At least one of the user's properties is required. | | | |

#### Response Fields

| Return Value | Type | Description |
| --- | --- | --- |
| Success | Boolean | Is the action executed successful or not. |
| Message | String | A message depending on the success of execution. When execution fails this will contain an errormessage. |
| TicketID | Int | The ID of the created ticket. |
| Subject | String | The subject you have submitted. |
| Description | String | The ticket description you have submitted. |
| CreationDate | DateTime | The creation date of the ticket. The date will be formatted following the ISO 8601 standard. e.g. '2015-05-06T15:43:54' |
| Type | String | The ticket type you have submitted. |
| Priority | String | The priority of the ticket you have submitted. |
| State | String | The ticket state you have submitted. |
| Team | String | The agent team you have submitted. |
| User | String | The user's displayname. |
| UserID | Int | The user's userid. |
| Agent | String | The agent's displayname. |
| AgentID | Int | The agent's userid. |
| AgentInitiated | Boolean | Is this ticket initiated by an agent. |
| Personal | Boolean | Is this a personal ticket. |
| CustomFields | Object | A JSON-object containing the inputted custom field(s) data. |
| Files | Array | An array containing the names (+extension) of the uploaded files. Note: this is only returned when files are passed. |

#### Example

##### Request Example

http://YourServerName:81/api.aspx?Action=AddTicket&Key=123456789&Subject=Example&Description=Example&Type=Hardware&Priority=High&Username=MyDomain\Earl&AgentUsername=MyDomain\John&Team=Information%20Technology

##### Response Example

{
"Success": true,
"Message": "The creation was successful.",
"Ticketid": 1,
"Subject": "Example",
"Description": "Example",
"CreationDate": "2017-07-18T11:36:58",
"Type": "Hardware",
"Priority": "high",
"State": "open",
"Team": "Information Technology",
"Agent": "John",
"AgentID": 2,
"User": "Earl",
"UserID": 1,
"FollowUp" : false,
"AgentInitiated": false,
"Personal": false
}

#### Example 2

##### Request Example

http://YourServerName:81/api.aspx?Action=AddTicket&Key=123456789&Subject=Example&Description=Example&Type=Development&Priority=High&Username=MyDomain\Earl&AgentUsername=MyDomain\John&Team=Information%20Technology&CustomFields=%7B"customFields"%3A%5B%7B"name"%3A"error"%2C"value"%3A"confirmed%20bug"%7D%5D%7D

##### Response Example

{
"Success": true,
"Message": "The creation was successful.",
"Ticketid": 120258,
"Subject": "Example",
"Text": "Example",
"CreationDate": "2017-07-18T11:36:58",
"Type": "Development",
"Priority": "high",
"State": "open",
"Team": "Information Technology",
"Agent": "John",
"AgentID": 2,
"User": "Earl",
"UserID": 1,
"AgentInitiated": false,
"Personal": false,
"CustomFields":
[
{"name":"error", "value":"confirmed bug"}
]
}

#### Example 3

##### Request Example

http://YourServerName:81/api.aspx?Action=AddTicket&Key=123456789&Subject=Example&Description=Example&Type=Development&Priority=High&Username=MyDomain\Earl&AgentUsername=MyDomain\John&Team=Information%20Technology&CustomFields=%7B%0A%20%20%20%20%22customFields%22%3A%20%5B%0A%20%20%20%20%20%20%20%20%7B%0A%20%20%20%20%20%20%20%20%20%20%20%20%22name%22%3A%20%22textCustomField%22%2C%0A%20%20%20%20%20%20%20%20%20%20%20%20%22value%22%3A%20%22text%20goes%20here.%22%0A%20%20%20%20%20%20%20%20%7D%2C%0A%20%20%20%20%20%20%20%20%7B%0A%20%20%20%20%20%20%20%20%20%20%20%20%22name%22%3A%20%22dateCustomField%22%2C%0A%20%20%20%20%20%20%20%20%20%20%20%20%22value%22%3A%20%222015-05-06T00%3A00%3A00%22%0A%20%20%20%20%20%20%20%20%7D%2C%0A%20%20%20%20%20%20%20%20%7B%0A%20%20%20%20%20%20%20%20%20%20%20%20%22name%22%3A%20%22textAreaCustomField%22%2C%0A%20%20%20%20%20%20%20%20%20%20%20%20%22value%22%3A%20%22text%20area%20content%20goes%20here.%22%0A%20%20%20%20%20%20%20%20%7D%2C%0A%20%20%20%20%20%20%20%20%7B%0A%20%20%20%20%20%20%20%20%20%20%20%20%22name%22%3A%20%22multiselectCustomField%22%2C%0A%20%20%20%20%20%20%20%20%20%20%20%20%22values%22%3A%20%5B%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%22a%22%2C%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%22b%22%2C%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%22c%22%2C%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%22d%22%0A%20%20%20%20%20%20%20%20%20%20%20%20%5D%0A%20%20%20%20%20%20%20%20%7D%2C%0A%20%20%20%20%20%20%20%20%7B%0A%20%20%20%20%20%20%20%20%20%20%20%20%22name%22%3A%20%22checkboxCustomField%22%2C%0A%20%20%20%20%20%20%20%20%20%20%20%20%22value%22%3A%20%22false%22%0A%20%20%20%20%20%20%20%20%7D%0A%20%20%20%20%5D%0A%7D

##### Response Example

{
"Success": true,
"Message": "The creation was successful.",
"Ticketid": 120258,
"Subject": "Example",
"Text": "Example",
"CreationDate": "2017-07-18T11:36:58",
"Type": "Development",
"Priority": "high",
"State": "open",
"Team": "Information Technology",
"Agent": "John",
"AgentID": 2,
"User": "Earl",
"UserID": 1,
"AgentInitiated": false,
"Personal": false,
"CustomFields":
[
{"name": "textCustomField", "value": "Text goes here."},
{"name": "dateCustomField", "value": "2015-05-06T00:00:00"},
{"name": "textAreaCustomField", "value": "Textarea content goes here."},
{"name": "multiSelectCustomField", "values": [ "a", "b", "c", "d" ]},
{"name": "checkBoxCustomField", "value": "false"}
]
}

#### Example 4 - Create a new ticket with 2 files attached

C# code

private static HttpWebResponse CreateHTTPPostWithFiles()
{
String boundary = String.Format("----------{0:N}", Guid.NewGuid());
Encoding encoding = Encoding.UTF8;
Stream formDataStream = new System.IO.MemoryStream();
//File
string header = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"; filename=\"{2}\"\r\nContent-Type: {3}\r\n\r\n",
boundary,
"tosendtxt", //unique identifier
"tosend.txt", //filename
"text/plain"); // default application/octet-stream
FileStream fs = new FileStream("C:\\tosend.txt", FileMode.Open, FileAccess.Read);
byte[] data = new byte[fs.Length];
fs.Read(data, 0, data.Length);
fs.Close();
formDataStream.Write(encoding.GetBytes(header), 0, encoding.GetByteCount(header));
// Write the file data directly to the Stream, rather than serializing it to a string.
formDataStream.Write(data, 0, data.Length);
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
//File
string header2 = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"; filename=\"{2}\"\r\nContent-Type: {3}\r\n\r\n",
boundary,
"imagelogo", //unique identifier
"lslogo.jpeg", //filename
"image/jpeg"); // default application/octet-stream
FileStream fs2 = new FileStream("C:\\lslogo.jpeg", FileMode.Open, FileAccess.Read);
byte[] data2 = new byte[fs2.Length];
fs2.Read(data2, 0, data2.Length);
fs2.Close();
formDataStream.Write(encoding.GetBytes(header2), 0, encoding.GetByteCount(header2));
// Write the file data directly to the Stream, rather than serializing it to a string.
formDataStream.Write(data2, 0, data2.Length);
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
//String Parameters
string postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"Key",
"123456789");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"action",
"AddTicket");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"subject",
"example");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"description",
"Ticket description here");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"priority",
"medium");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"email",
"example@mail.com");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"displayname",
"displayname here");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"username",
"MyDomain\\Filip");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
//Insert other parameters...
//Create footer
string footer = "\r\n--" + boundary + "--\r\n";
formDataStream.Write(encoding.GetBytes(footer), 0, encoding.GetByteCount(footer));
// Dump the Stream into a byte[]
formDataStream.Position = 0;
byte[] formData = new byte[formDataStream.Length];
formDataStream.Read(formData, 0, formData.Length);
formDataStream.Close();
//{hostname:port/api.aspx}
HttpWebRequest request = WebRequest.Create("http://localhost:86/api.aspx") as HttpWebRequest;
// Set up the request properties.
request.Method = "POST";
request.ContentType = "multipart/form-data; boundary=" + boundary;
request.ContentLength = formData.Length;
// You could add authentication here as well if needed:
// request.PreAuthenticate = true;
// request.AuthenticationLevel = System.Net.Security.AuthenticationLevel.MutualAuthRequested;
// request.Headers.Add("Authorization", "Basic " + Convert.ToBase64String(System.Text.Encoding.Default.GetBytes("username" + ":" + "password")));
// Send the form data to the request.
using (Stream requestStream = request.GetRequestStream())
{
requestStream.Write(formData, 0, formData.Length);
requestStream.Close();
}
return request.GetResponse() as HttpWebResponse;
}

##### Response Example

{
"Success": true,
"Message": "The creation was successful.",
"TicketID": 417478,
"Subject": "example",
"Description": "Ticket description here",
"CreationDate": "2015-12-07T10:03:09",
"Type": "[Cleverbridge] Paid",
"Priority": "medium",
"State": "Open",
"Team": "CleverFollowUp",
"Agent": "",
"AgentID": 0,
"User": "displayname here",
"UserID": 65305,
"FollowUp": false,
"AgentInitiated": false,
"Personal": false,
"Custom fields": {},
"Files":
[
"tosend.txt",
"lslogo.jpeg"
]
}

#### Example 5 - Create a new ticket containing an embedded image

C# code

private static HttpWebResponse CreateHTTPPostWithEmbededImage()
{
String boundary = String.Format("----------{0:N}", Guid.NewGuid());
Encoding encoding = Encoding.UTF8;
Stream formDataStream = new System.IO.MemoryStream();
//File (image to embed)
string header = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"; filename=\"{2}\"\r\nContent-Type: {3}\r\n\r\n",
boundary,
"screenshottoembed", //unique identifier
"screenshottoembed.jpg", //filename
"image/jpeg"); // default application/octet-stream
FileStream fs = new FileStream("C:\\screenshottoembed.jpg", FileMode.Open, FileAccess.Read);
byte[] data = new byte[fs.Length];
fs.Read(data, 0, data.Length);
fs.Close();
formDataStream.Write(encoding.GetBytes(header), 0, encoding.GetByteCount(header));
// Write the file data directly to the Stream, rather than serializing it to a string.
formDataStream.Write(data, 0, data.Length);
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
//String Parameters
string postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"Key",
"123456789");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"action",
"AddTicket");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"subject",
"example");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
//Put the image to embed in the description parameter (inside the src tag of an img element).
//Notation: cid:filename.extension@\*\*\*\*.\*\*\*\* (\* = a-z/A-Z/0-9)
//\*\*\*\*.\*\*\*\* (for instance: 8ee61793.947a25ef) is the unique id of the image. This may be random but must consist only of a-z/A-Z/0-9 characters.
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"description",
@"![]()");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"priority",
"medium");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"email",
"example@mail.com");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"displayname",
"displayname here");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"username",
"MyDomain\\Filip");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
//Insert other parameters...
//Create footer
string footer = "\r\n--" + boundary + "--\r\n";
formDataStream.Write(encoding.GetBytes(footer), 0, encoding.GetByteCount(footer));
// Dump the Stream into a byte[]
formDataStream.Position = 0;
byte[] formData = new byte[formDataStream.Length];
formDataStream.Read(formData, 0, formData.Length);
formDataStream.Close();
//{hostname:port/api.aspx}
HttpWebRequest request = WebRequest.Create("http://localhost:86/api.aspx") as HttpWebRequest;
// Set up the request properties.
request.Method = "POST";
request.ContentType = "multipart/form-data; boundary=" + boundary;
request.ContentLength = formData.Length;
// You could add authentication here as well if needed:
// request.PreAuthenticate = true;
// request.AuthenticationLevel = System.Net.Security.AuthenticationLevel.MutualAuthRequested;
// request.Headers.Add("Authorization", "Basic " + Convert.ToBase64String(System.Text.Encoding.Default.GetBytes("username" + ":" + "password")));
// Send the form data to the request.
using (Stream requestStream = request.GetRequestStream())
{
requestStream.Write(formData, 0, formData.Length);
requestStream.Close();
}
return request.GetResponse() as HttpWebResponse;
}

##### Response Example

{
"Success": true,
"Message": "The creation was successful.",
"TicketID": 417495,
"Subject": "example",
"Description": "![\"screenshottoembed.jpg\"](\"cid:screenshottoembed.jpg@8ee61793.947a25ef\")",
"CreationDate": "2015-12-07T14:35:07",
"Type": "[Cleverbridge] Paid",
"Priority": "medium",
"State": "Open",
"Team": "CleverFollowUp",
"Agent": "",
"AgentID": 0,
"User": "displayname here",
"UserID": 65305,
"FollowUp": false,
"AgentInitiated": false,
"Personal": false,
"Custom fields": {},
"Files":
[
"screenshottoembed.jpg"
]
}

### EditTicket

- Name: EditTicket
- Method: POST
- URL: /api.aspx?action=EditTicket&key={key}

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| TicketID | Int | True | The ID of the ticket you want to edit. You receive the ID when creating the ticket. |
| Subject | String | False | The subject of the ticket. |
| Description | String | False | The description of the ticket. |
| State | String | False | The ticket state. Standard types are : Open, Pending, Closed, Awaiting Order. Other states can be added in the website. |
| Type | String | False | The ticket type. Standard types are : Hardware, Internet, Intranet, Network, Operating System, Sales, Services, Support. Other types can be added in the website. |
| Priority | String | False | The priority of a ticket. Standard priorities are : Low, Medium, High. Other priorities can be added in the website. |
| Team | String | False | The agent team you want your ticket send to. Standard teams are : Sales, Information Technology, Administration. Other team can be added in the website. |
| Username | String | False\* | The login username (domain\username) of the user who sends the ticket.     When no user is found the API will try to create a new one with an existing AD user based on the entered username and/or email. When no AD user is found the system will try to create a Non-AD user if you entered a displayname and email. If only the email is entered, the email is used as displayname. When none of these properties are given no user can be found or created and the ticket creation will fail. |
| Displayname | String | False | The displayname of the user who sends the ticket. The system will not search on displayname. However, it will use this when a new user is created.     When no user is found the API will try to create a new one with an existing AD user based on the entered username and/or email. When no AD user is found the system will try to create a Non-AD user if you entered a displayname and email. If only the email is entered, it is used as displayname. When none of these properties are given no user can be found or created and the ticket creation will fail. |
| Email | String | False\* | The email of the user who sends the ticket.     When no user is found the API will try to create a new one with an existing AD user based on the entered username and/or email. When no AD user is found the system will try to create a Non-AD user if you entered a displayname and email. If only the email is entered, it is used as displayname. When none of these properties are given no user can be found or created and the ticket creation will fail. |
| AgentUsername | String | False | The domain and username of the assigned agent. Format: domain\username |
| AgentEmail | String | False | The email of the assigned agent. |
| Subscribers | String | False | A comma separated list of agent names (domain\username) or agent id's to add as subscribers. |
| Unsubscribers | String | False | A comma separated list of agent names (domain\username) or agent id's to remove as subscribers. |
| FollowUp | Boolean | False | You can add a follow-up to a ticket to flag it. If no FollowUpDuration or FollowUpDate has been added then the follow-up will have no date. |
| FollowUpDuration | Integer | False | The follow-up duration in days. |
| FollowUpDate | DateTime | False | The follow-up date. The date should be formatted following the ISO 8601 standard. e.g. '2017-10-06'. |
| Unassign | Boolean | False | To unassign a ticket from an agent, set this value to true. This will override setting the AgentEmail or AgentUsername. |
| Personal | Boolean | False | Users will be allowed to see the agents name in a ticket when personal is set to true. |
| \* At least one of the user's properties is required. | | | |

#### Response Fields

| Return Value | Type | Description |
| --- | --- | --- |
| Success | Boolean | Is the action executed successful or not. |
| Message | String | A message depending on the success of execution. When execution fails this will contain an errormessage. |
| TicketID | Int | The ticket ID you have submitted. |
| Subject | String | The subject of the ticket. |
| Description | String | The description of the ticket. |
| CreationDate | DateTime | The creation date of the ticket. The date will be formatted following the ISO 8601 standard. e.g. '2015-05-06T15:43:54' |
| Type | String | The type of the updated ticket. If updating fails this will have the old value. |
| Priority | String | The priority of the updated ticket. If updating fails this will have the old value. |
| State | String | The state of the updated ticket. If updating fails this will have the old value. |
| Team | String | The agent team of the updated ticket. If updating fails this will have the old value. |
| User | String | The user's displayname of the updated ticket. If updating fails this will have the old value. |
| UserID | Int | The user's userid of the updated ticket. If updating fails this will have the old value. |
| Agent | String | The agent's displayname of the updated ticket. If updating fails this will have the old value. |
| AgentID | Int | The agent's userid of the updated ticket. If updating fails this will have the old value. |
| FollowUp | Boolean | Is the updated ticket followed-up or not. If updating fails this will have the old value. |
| FollowUpDate | DateTime | The follow-up date which is set. When removing the follow-up this will return '0001-01-01T00:00:00'. When setting the follow-up date to 'no date' this will return '1900-01-01T00:00:00'. |
| Subscribers | String array | The list of agent id's subscribed to this ticket. |
| Updated | DateTime | The timestamp of the successful update. |
| Personal | Boolean | Users will be allowed to see the agents name in a ticket when personal is set to true. |

#### Example

##### Request Example

http://YourServerName:81/api.aspx?Action=EditTicket&Key=123456789&TicketID=1&Subject=Example subject&Description=Example description&Type=Network&Priority=Medium&State=Closed&Username=MyDomain\Jack&AgentUsername=MyDomain\William&Team=Sales&Followup=true&Personal=true

##### Response Example

{
"Ticketid": 1,
"Subject": "Example subject",
"Description": "Example description",
"CreationDate": "2017-07-18T11:36:58",
"Type": "Network",
"Priority": "Medium",
"State": "Closed",
"Team": "Sales",
"Agent": "William",
"AgentID": 3,
"UserID": 4,
"User": "Jack",
"FollowUp": true,
"FollowUpDate": "1900-01-01T00:00:00",
"Subscribers":
[
8,
5,
],
"Updated": null,
"IsPersonal": false,
"Success": true,
"Message": "The update was successful."
}

### GetTicket

- Name: GetTicket
- Method: GET
- URL: /api.aspx?action=GetTicket&key={key}

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| TicketID | Int | True | The ID of the ticket you want. You receive the ID when creating the ticket. |

#### Response Fields

| Return Value | Type | Description |
| --- | --- | --- |
| Success | Boolean | Is the action executed successful or not. |
| Message | String | A message depending on the success of execution. When execution fails this will contain an errormessage. |
| TicketID | Int | The ticket ID you have submitted. |
| Subject | String | The ticket subject. |
| CreationDate | DateTime | The creation date of the ticket. The date will be formatted following the ISO 8601 standard. e.g. '2015-05-06T15:43:54' |
| Type | String | The ticket type. |
| Priority | String | The ticket priority. |
| State | String | The ticket state. |
| Team | String | The agent team the ticket belongs to. |
| User | String | The senders displayname. |
| UserID | Int | The senders userid. |
| Agent | String | The displayname of the agent to who the ticket is sent to. |
| AgentID | Int | The userid of the agent to who the ticket is sent to. |
| FollowUp | Boolean | Is the ticket followed-up or not. |

#### Example

##### Request Example

http://YourServerName:81/api.aspx?Action=GetTicket&Key=123456789&TicketID=1

##### Response Example

{
"Success": true,
"Message": "The update was successful.",
"Ticketid": 6,
"Subject": "test",
"CreationDate": "2017-07-18T11:36:58",
"Type": "Hardware",
"Priority": "High",
"State": "Closed",
"Team": "Information Technology",
"Agent": "John",
"AgentID": 2,
"User": "Earl",
"UserID": 1,
"FollowUp": true
}

### AddNote

- Name: AddNote
- Method: POST
- URL: /api.aspx?action=AddNote&key={key}

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| TicketID | Int | True | The ID of the ticket you want to add a note to. You receive the ID when creating the ticket. |
| Text | String | True | The text of the note. |
| Username | String | False\* | The username (domain\username) of who sends the note. Users other than the ticket creator or agents will be added as CC user.     When no user is found the API will try to create a new one with an existing AD user based on the entered username and/or email. When no AD user is found the system will try to create a Non-AD user if you entered a displayname and email. If only the email is entered, the email is used as displayname. When none of these properties are given no user can be found or created and the ticket creation will fail. |
| Displayname | String | False | The displayname of the user who sends the note. The system will not search on displayname. However, it will use this when a new user is created.     When no user is found the API will try to create a new one with an existing AD user based on the entered username and/or email. When no AD user is found the system will try to create a Non-AD user if you entered a displayname and email. If only the email is entered, it is used as displayname. When none of these properties are given no user can be found or created and the ticket creation will fail. |
| Email | String | False\* | The email of who sends the note. Users other than the ticket creator or agents will be added as CC user.     When no user is found the API will try to create a new one with an existing AD user based on the entered username and/or email. When no AD user is found the system will try to create a Non-AD user if you entered a displayname and email. If only the email is entered, the email is used as displayname. When none of these properties are given no user can be found or created and the ticket creation will fail. |
| Type | String | False | The type of the note. Possible types are: Public or Internal. When no value is passed the type is public. |
| Files | File(s) | False | The files you want to add as attachment to a note.    Note that you can not add these as parameter of a URL and you'll need to use a script to generate a post containing the files. For more information on how to do this you can check the examples underneath. |
| \* At least one of the user's properties is required. | | | |

#### Response Fields

| Return Value | Type | Description |
| --- | --- | --- |
| Success | Boolean | Is the action executed successful or not. |
| Message | String | A message depending on the success of execution. When execution fails this will contain an errormessage. |
| TicketID | Int | The ticket ID you have submitted. |
| Subject | String | The ticket subject. |
| NoteID | Int | The ID of the created note. |
| Text | String | The text of the note you have submitted. |
| User | String | The displayname of the user you have submitted. |
| UserID | Int | The userid of the user you have submitted. |
| CreationDate | DateTime | The creation date of the note (Current date). The date will be formatted following the ISO 8601 standard. e.g. '2015-05-06T15:43:54' |
| Type | String | The type of the note. |
| Files | Array | An array containing the names (+extension) of the uploaded files. Note: this is only returned when files are passed. |

#### Example

##### Request Example

http://YourServerName:81/api.aspx?Action=AddNote&Key=123456789&TicketID=1&Text=Example&Username=MyDomain\John&Type=Public

##### Response Example

{
"Success": true,
"Message": "The update was successful.",
"Ticketid": 1,
"Subject": "Example",
"Noteid": 1,
"Text": "Example",
"User": "John",
"UserID": 2,
"CreationDate": "2017-07-18T11:36:58"
}

#### Example 2 - Create a new note with 2 files attached

C# code

private static HttpWebResponse CreateHTTPPostWithFiles()
{
String boundary = String.Format("----------{0:N}", Guid.NewGuid());
Encoding encoding = Encoding.UTF8;
Stream formDataStream = new System.IO.MemoryStream();
//File
string header = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"; filename=\"{2}\"\r\nContent-Type: {3}\r\n\r\n",
boundary,
"tosendtxt", //unique identifier
"tosend.txt", //filename
"text/plain"); // default application/octet-stream
FileStream fs = new FileStream("C:\\tosend.txt", FileMode.Open, FileAccess.Read);
byte[] data = new byte[fs.Length];
fs.Read(data, 0, data.Length);
fs.Close();
formDataStream.Write(encoding.GetBytes(header), 0, encoding.GetByteCount(header));
// Write the file data directly to the Stream, rather than serializing it to a string.
formDataStream.Write(data, 0, data.Length);
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
//File
string header2 = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"; filename=\"{2}\"\r\nContent-Type: {3}\r\n\r\n",
boundary,
"imagelogo", //unique identifier
"lslogo.jpeg", //filename
"image/jpeg"); // default application/octet-stream
FileStream fs2 = new FileStream("C:\\lslogo.jpeg", FileMode.Open, FileAccess.Read);
byte[] data2 = new byte[fs2.Length];
fs2.Read(data2, 0, data2.Length);
fs2.Close();
formDataStream.Write(encoding.GetBytes(header2), 0, encoding.GetByteCount(header2));
// Write the file data directly to the Stream, rather than serializing it to a string.
formDataStream.Write(data2, 0, data2.Length);
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
//String Parameters
string postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"Key",
"123456789");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"Action",
"AddNote");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"TicketID",
480409);
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"Text",
"Note Text");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"Email",
"example@mail.com");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"Type",
"Public");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
//Insert other parameters...
//Create footer
string footer = "\r\n--" + boundary + "--\r\n";
formDataStream.Write(encoding.GetBytes(footer), 0, encoding.GetByteCount(footer));
// Dump the Stream into a byte[]
formDataStream.Position = 0;
byte[] formData = new byte[formDataStream.Length];
formDataStream.Read(formData, 0, formData.Length);
formDataStream.Close();
//{hostname:port/api.aspx}
HttpWebRequest request = WebRequest.Create("http://localhost:86/api.aspx") as HttpWebRequest;
// Set up the request properties.
request.Method = "POST";
request.ContentType = "multipart/form-data; boundary=" + boundary;
request.ContentLength = formData.Length;
// You could add authentication here as well if needed:
// request.PreAuthenticate = true;
// request.AuthenticationLevel = System.Net.Security.AuthenticationLevel.MutualAuthRequested;
// request.Headers.Add("Authorization", "Basic " + Convert.ToBase64String(System.Text.Encoding.Default.GetBytes("username" + ":" + "password")));
// Send the form data to the request.
using (Stream requestStream = request.GetRequestStream())
{
requestStream.Write(formData, 0, formData.Length);
requestStream.Close();
}
return request.GetResponse() as HttpWebResponse;
}

##### Response Example

{
"Success": true,
"Message": "The creation was successful." ,
"TicketID": 480409,
"Subject": "Example",
"Noteid": 839542,
"Text": "Note Text",
"User": "John",
"UserID": 99486,
"CreationDate": "2017-07-18T11:36:58",
"Type": "Public",
"Files":
[
"tosend.txt",
"lslogo.jpeg"
]
}

#### Example 3 - Create a new note containing an embedded image

C# code

private static HttpWebResponse CreateHTTPPostWithEmbedImage()
{
String boundary = String.Format("----------{0:N}", Guid.NewGuid());
Encoding encoding = Encoding.UTF8;
Stream formDataStream = new System.IO.MemoryStream();
//File (image to embed)
string header = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"; filename=\"{2}\"\r\nContent-Type: {3}\r\n\r\n",
boundary,
"screenshottoembed", //unique identifier
"screenshottoembed.jpg", //filename
"image/jpeg"); // default application/octet-stream
FileStream fs = new FileStream("C:\\screenshottoembed.png", FileMode.Open, FileAccess.Read);
byte[] data = new byte[fs.Length];
fs.Read(data, 0, data.Length);
fs.Close();
formDataStream.Write(encoding.GetBytes(header), 0, encoding.GetByteCount(header));
// Write the file data directly to the Stream, rather than serializing it to a string.
formDataStream.Write(data, 0, data.Length);
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
//String Parameters
string postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"Key",
"123456789");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"Action",
"AddNote");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"TicketID",
480409);
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
//Put the image to embed in the text parameter (inside the src tag of an img element).
//Notation: cid:filename.extension@\*\*\*\*.\*\*\*\* (\* = a-z/A-Z/0-9)
//\*\*\*\*.\*\*\*\* (for instance: 8ee61793.947a25ef) is the unique id of the image. This may be random but must consist only of a-z/A-Z/0-9 characters.
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"Text",
@"![]()");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"Email",
"example@mail.com");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
postData = string.Format("--{0}\r\nContent-Disposition: form-data; name=\"{1}\"\r\n\r\n{2}",
boundary,
"Type",
"Public");
formDataStream.Write(encoding.GetBytes(postData), 0, encoding.GetByteCount(postData));
formDataStream.Write(encoding.GetBytes("\r\n"), 0, encoding.GetByteCount("\r\n"));
//Insert other parameters...
//Create footer
string footer = "\r\n--" + boundary + "--\r\n";
formDataStream.Write(encoding.GetBytes(footer), 0, encoding.GetByteCount(footer));
// Dump the Stream into a byte[]
formDataStream.Position = 0;
byte[] formData = new byte[formDataStream.Length];
formDataStream.Read(formData, 0, formData.Length);
formDataStream.Close();
//{hostname:port/api.aspx}
HttpWebRequest request = WebRequest.Create("http://localhost:86/api.aspx") as HttpWebRequest;
// Set up the request properties.
request.Method = "POST";
request.ContentType = "multipart/form-data; boundary=" + boundary;
request.ContentLength = formData.Length;
// You could add authentication here as well if needed:
// request.PreAuthenticate = true;
// request.AuthenticationLevel = System.Net.Security.AuthenticationLevel.MutualAuthRequested;
// request.Headers.Add("Authorization", "Basic " + Convert.ToBase64String(System.Text.Encoding.Default.GetBytes("username" + ":" + "password")));
// Send the form data to the request.
using (Stream requestStream = request.GetRequestStream())
{
requestStream.Write(formData, 0, formData.Length);
requestStream.Close();
}
return request.GetResponse() as HttpWebResponse;
}

##### Response Example

{
"Success": true,
"Message": "The creation was successful.",
"TicketID": 480409,
"Subject": "Example",
"Noteid": 839546,
"Text": "![\"screenshottoembed.jpg\"](\"cid:screenshottoembed.jpg@8ee61793.947a25ef\")",
"User": "John",
"UserID": 99486,
"CreationDate": "2017-07-18T11:36:58",
"Type": "Public",
"Files":
[
"screenshottoembed.jpg"
]
}

### EditNote

- Name: EditNote
- Method: POST
- URL: /api.aspx?action=EditNote&key={key}

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| NoteID | Int | True | The ID of the note you want to edit. You receive the ID when creating the note. |
| Text | String | False | The text you want to edit the current text with. |

#### Response Fields

| Return Value | Type | Description |
| --- | --- | --- |
| Success | Boolean | Is the action executed successful or not. |
| Message | String | A message depending on the success of execution. When execution fails this will contain an errormessage. |
| TicketID | Int | The ticket ID of the note. |
| Subject | String | The subject of the ticket of the note. |
| NoteID | String | The note ID you have submitted. |
| Text | String | The updated text of the note. If updating fails this will have the old value. |
| User | String | The user's displayname of the updated note. If updating fails this will have the old value. |
| UserID | Int | The user's userid of the updated note. If updating fails this will have the old value. |
| CreationDate | DateTime | The creation date of the note. The date will be formatted following the ISO 8601 standard. e.g. '2015-05-06T15:43:54' |

#### Example

##### Request Example

http://YourServerName:81/api.aspx?Action=EditNote&Key=123456789&NoteID=1&Text=New%20Example

##### Response Example

{
"Success": true,
"Message": "The update was successful.",
"Noteid": 1,
"Text": "New Example",
"User": "John",
"UserID": 2,
"CreationDate": "2017-07-18T11:36:58",
"Ticketid": 1,
"Subject": "Example"
}

### GetNotes

- Name: GetNotes
- Method: GET
- URL: /api.aspx?action=GetNotes&key={key}

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| TicketID | Int | True | The ID of the ticket of which you want the notes. You receive the ID when creating the ticket. |

#### Response Fields

| Return Value | Type | Description |
| --- | --- | --- |
| Success | Boolean | Is the action executed successful or not. |
| Message | String | A message depending on the success of execution. When execution fails this will contain an errormessage. |
| TicketID | Int | The ticket ID of the requested assets. |
| Subject | String | The subject of the ticket of the requested assets. |
| Notes | Array | The requested notes with their note ID, text, user and creation date. |

#### Example

##### Request Example

http://YourServerName:81/api.aspx?Action=GetNotes&Key=123456789&TicketID=1

##### Response Example

{
"Success": true,
"Message": "The assigned assets are successfully returned",
"Ticketid": 1,
"Subject": "Example",
"Notes":
[
{"NoteID" : 1 , "Text" : "Example", "User": "John", "UserID": 2, "CreationDate": "2017-07-18T11:36:58"},
{"NoteID" : 2 , "Text" : "Example2", "User": "Earl", "UserID": 1, "CreationDate": "2017-07-18T11:39:58"}
]
}

### AddAsset

- Name: AddAsset
- Method: POST
- URL: /api.aspx?action=AddAsset&key={key}

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| TicketID | Int | True | The ID of the ticket you want to assign an asset to. You receive the ID when creating the ticket. |
| AssetName | String | False (Assetname or IP is Required) | The name of an asset in the system. |
| IPAddress | String | False (Assetname or IP is Required) | The ip-address of an asset in the system. |

#### Response Fields

| Return Value | Type | Description |
| --- | --- | --- |
| Success | Boolean | Is the action executed successful or not. |
| Message | String | A message depending on the success of execution. When execution fails this will contain an errormessage. |
| TicketID | Int | The ticket ID you have submitted. |
| Subject | String | The ticket subject. |
| AssetName | String | The name of the asset you have submitted. |
| IPAddress | String | The ip-address of the asset you have submitted. |

#### Example

##### Request Example

http://YourServerName:81/api.aspx?Action=AddAsset&Key=123456789&TicketID=1&Assetname=PC1&IPAdress=192.168.1.10

##### Response Example

{
"Success": true,
"Message": "The asset has been successfully assigned.",
"Ticketid": 1,
"Subject": "Example",
"Assetname": "PC1",
"IPAddress": "192.168.1.10"
}

### RemoveAsset

- Name: RemoveAsset
- Method: POST
- URL: /api.aspx?action=RemoveAsset&key={key}

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| TicketID | Int | True | The ID of the ticket of which you want to remove an asset. You receive the ID when creating the ticket. |
| AssetName | String | True | The name of the asset you want to remove. |
| IPAddress | String | True | The ip-address of the asset you want to remove. |

#### Response Fields

| Return Value | Type | Description |
| --- | --- | --- |
| Success | Boolean | Is the action executed successful or not. |
| Message | String | A message depending on the success of execution. When execution fails this will contain an errormessage. |
| TicketID | Int | The ticket ID you have submitted. |
| Subject | String | The ticket subject. |
| AssetName | String | The name of the asset you have submitted. |
| IPAddress | String | The ip-address of the asset you have submitted. |

#### Example

##### Request Example

http://YourServerName:81/api.aspx?Action=RemoveAsset&Key=123456789&TicketID=1&Assetname=PC1&IPAdress=192.168.1.10

##### Response Example

{
"Success": true,
"Message": "The asset has been unassigned",
"Ticketid": 1,
"Subject": "Example",
"Assetname": "PC1",
"IPAddress": "192.168.1.10"
}

### GetAssets

- Name: GetAssets
- Method: GET
- URL: /api.aspx?action=GetAssets&key={key}

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| TicketID | Int | True | The ID of the ticket of which you want the assigned assets. You receive the ID when creating the ticket. |

#### Response Fields

| Return Value | Type | Description |
| --- | --- | --- |
| Success | Boolean | Is the action executed successful or not. |
| Message | String | A message depending on the success of execution. When execution fails this will contain an errormessage. |
| TicketID | Int | The ticket ID of the requested assets. |
| Subject | String | The subject of the ticket of the requested assets. |
| Assets | Array | The requested assets with their asset name and ip-address. |

#### Example

##### Request Example

http://YourServerName:81/api.aspx?Action=GetAssets&Key=123456789&TicketID=1

##### Response Example

{
"Success": true,
"Message": "The assigned assets are successfully returned",
"Ticketid": 1,
"Subject": "Example",
"Assets":
[
{"assetname" : "PC1", "ipaddress" : "192.168.1.10"},
{"assetname" : "PC2", "ipaddress" : "192.168.1.11"}
]
}

### SearchTickets

- Name: SearchTickets
- Method: GET
- URL: /api.aspx?action=SearchTickets&key={key}

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| MaxResults | Int | False | The maximum number of results. If the tickets count is higher that this number, the list of tickets will not be returned. If this parameter is not specified the maximum number of results is 100. |
| State | String | False | The ticket state. |
| Priority | String | False | The ticket priority. |
| FromUserId | Int | False | The is of the user who initiated the ticket. |
| AgentId | Int | False | The id of the agent assigned to the ticket. |
| Flagged | Boolean | False | Indicate if there is a follow up on the ticket or not. |
| MinDate | DateTime | False | Search for tickets created after this date. |
| MaxDate | DateTime | False | Search for tickets created before this date. |
| Description | String | False | Ticket description. |
| Subject | String | False | Ticket subject. |
| Type | String | False | Ticket type. |

#### Response Fields

| Return Value | Type | Description |
| --- | --- | --- |
| Success | Boolean | Is the action executed successful or not. |
| Message | String | A message depending on the success of execution. When execution fails this will contain an errormessage. |
| Count | Int | The number of tickets that match the search criteria. |
| Tickets | Array | A list of ticket id's that match the search criteria. |

#### Example

##### Request Example

http://YourServerName:81/api.aspx?Action=SearchTickets&Key=123456789&State=closed&Priority=high&AgentId=4

##### Response Example

{
"Success": true,
"Message": "The search was successful",
"Count": 6,
"Results":
[
436389,
437769,
449753,
452865,
458968,
481911
]
}

### SearchUsers

- Name: SearchUsers
- Method: GET
- URL: /api.aspx?action=SearchUsers&key={key}

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| MaxResults | Int | False | The maximum number of results. If the users found is higher that this number, the list of users will not be returned. If this parameter is not specified the maximum number of results is 100. |
| Email | String | False | The email or part of the email of the user(s). |
| Name | String | False | The name or part of the name of the user(s). |
| Upn | String | False | The UPN or part of the UPN of the user(s). |
| Username | String | False | The username or part of the username of the user(s). |
| UserDomain | String | False | The domain or part of the domain of the user(s). |
| Description | String | False | The description or part of the description of the user(s). |
| Address | String | False | The address or part of the address of the user(s). |
| Telephone | String | False | The telephone or part of the telephone of the user(s). |
| Mobile | String | False | The mobile or part of the mobile of the user(s). |
| Fax | String | False | The fax or part of the fax of the user(s). |
| Company | String | False | The company or part of the company of the user(s). |
| Department | String | False | The department or part of the department of the user(s). |

#### Response Fields

| Return Value | Type | Description |
| --- | --- | --- |
| Success | Boolean | Is the action executed successful or not. |
| Message | String | A message depending on the success of execution. When execution fails this will contain an errormessage. |
| Count | Int | The number of users that match the search criteria. |
| Tickets | Array | A list of user id's that match the search criteria. |

#### Example

##### Request Example

http://YourServerName:81/api.aspx?Action=SearchUsers&Key=123456789&Name=marc

##### Response Example

{
"Success": true,
"Message": "The search was successful",
"Count": 6,
"Results":
[
68082,
63921,
102746,
98728,
96536,
73447
]
}

### EditTicketCustomField

- Name: EditTicketCustomField
- Method: POST
- URL: /api.aspx?action=EditTicketCustomField&key={key}

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| TicketID | Int | True | The ID of the ticket of which you want the assigned assets. You receive the ID when creating the ticket. |
| CustomFieldName | String | True | The name of the custom field you want to fill in or edit. |
| CustomFieldValue | String | False\* | The value of the custom field you want to fill in or edit. |
| CustomFieldValues | String | False\* | The values of the custom field you want to fill in or edit. Values must be comma seperated. |
| CustomFieldJSON | String | False\* | The key value pair of the custom field you want to fill in or edit. Must be in valid JSON-format. Should contain only one key value pair. Note: If sent via querystring, the JSON-object must be URL-encoded. |
| \*The following combinations are possible:   CustomFieldName and CustomFieldValue(s) CustomFieldJSON | | | |

#### Response Fields

| Return Value | Type | Description |
| --- | --- | --- |
| Success | Boolean | Is the action executed successful or not. |
| Message | String | A message depending on the success of execution. When execution fails this will contain an errormessage. |
| TicketID | Int | The ticket ID of the requested assets. |
| CustomFieldName | String | The name of the custom field you filled in or edited. |
| CustomFieldValue | String | The value of the custom field you filled in or edited. |

#### Example 1

##### Request Example

http://YourServerName:81/api.aspx?Action=EditTicketCustomField&Key=123456789&TicketID=1&CustomFieldName=customFieldTextBox&CustomFieldValue=textvalue

##### Response Example

{
"Success": true,
"Message": "The creation was successful.",
"TicketID": 1,
"CustomFieldName": "customFieldTextBox",
"CustomFieldValue": "textvalue"
}

#### Example 2

##### Request Example

http://YourServerName:81/api.aspx?Action=EditTicketCustomField&Key=123456789&TicketID=1&CustomFieldName=customFieldMultiSelect&CustomFieldValues=e,f,g,h

##### Response Example

{
"Success": true,
"Message": "The creation was successful.",
"TicketID": 15,
"CustomFieldName": "customFieldMultiSelect",
"CustomFieldValues": "e,f,g,h"
}

#### Example 3

JSON-object (CustomFieldJSON).
{
"name": "customFieldMultiSelect",
"values":
[
"e",
"f",
"g",
"h"
]
}
##### Request Example

http://YourServerName:81/api.aspx?Action=EditTicketCustomField&Key=123456789&TicketID=15&CustomFieldJSON=%7B%0A%20%20%20%20%22name%22%3A%20%22customFieldMultiSelect%22%2C%0A%20%20%20%20%22values%22%3A%20%5B%0A%20%20%20%20%20%20%20%20%22e%22%2C%0A%20%20%20%20%20%20%20%20%22f%22%2C%0A%20%20%20%20%20%20%20%20%22g%22%2C%0A%20%20%20%20%20%20%20%20%22h%22%0A%20%20%20%20%5D%0A%7D

##### Response Example
{
"Success": true,
"Message": "The creation was successful.",
"TicketID": 15,
"CustomFieldName": "customFieldMultiSelect",
"CustomFieldValues": "e,f,g,h"
}

### DeleteTicketCustomField

- Name: DeleteTicketCustomField
- Method: POST
- URL: /api.aspx?action=DeleteTicketCustomField&key={key}

#### Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| TicketID | Int | True | The ID of the ticket of which you want the assigned assets. You receive the ID when creating the ticket. |
| CustomFieldName | String | True | The name of the custom field you want to fill in or edit. |

#### Response Fields

| Return Value | Type | Description |
| --- | --- | --- |
| Success | Boolean | Is the action executed successful or not. |
| Message | String | A message depending on the success of execution. When execution fails this will contain an errormessage. |
| TicketID | Int | The ticket ID of the requested assets. |
| CustomFieldName | String | The name of the custom field of which you want to delete the value. |

#### Example

##### Request Example

http://YourServerName:81/api.aspx?Action=DeleteTicketCustomField&Key=123456789&TicketID=1&CustomFieldName=customFieldTextBox

##### Response Example

{
"Success": true,
"Message": "The deletion was successful.",
"TicketID": 15,
"CustomFieldName": "customFieldTextBox"
}
