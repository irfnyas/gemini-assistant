import 'dart:developer';

import 'package:chat_bubbles/chat_bubbles.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:gsheets/gsheets.dart';
import 'package:myapp/env.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      debugShowCheckedModeBanner: false,
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // vars
  final messageList = <({String text, bool isSender})>[];
  var taskList = <String>[];
  var isLoading = false;

  // model tools
  Future<Map<String, Object?>> createTask(
    Map<String, Object?> args,
  ) async {
    if (args['task'] != null) {
      try {
        final gsheets = GSheets(googleServiceAccount);
        final spreadsheet = await gsheets.spreadsheet(spreadsheetId);
        final worksheet = spreadsheet.worksheetByIndex(0);
        final task = '${args['task']}';
        await worksheet?.values.insertValue(task, column: 1, row: 1);
      } catch (e) {
        showErrorSnackbar('$e');
      }
    }

    return {'tasks': taskList};
  }

  final createTaskTool = FunctionDeclaration(
    'createTask',
    'add a new task to the task list.',
    Schema(
      SchemaType.object,
      properties: {
        'task': Schema(
          SchemaType.string,
          description: 'the new task',
        ),
      },
      requiredProperties: ['task'],
    ),
  );

  // View Model
  void Function(String)? messageOnSend() {
    return isLoading ? null : (text) => sendMessage(text);
  }

  Future<void> sendMessage(String text) async {
    try {
      // return if still loading
      if (isLoading) return;

      // hide keyboard
      FocusManager.instance.primaryFocus?.unfocus();

      // add user message to list
      final userMsg = (text: text, isSender: true);
      setState(() {
        isLoading = true;
        messageList.insert(0, userMsg);
      });

      // send message to AI model
      const modelName = 'gemini-1.5-flash';
      final functionDeclarations = [createTaskTool];

      final model = GenerativeModel(
        model: modelName,
        apiKey: apiKey,
        systemInstruction: Content.system(systemInstruction),
        tools: [Tool(functionDeclarations: functionDeclarations)],
      );

      final chat = model.startChat(
        history: messageList.reversed
            .take(messageList.length - 1)
            .map((e) => e.isSender
                ? Content.text(e.text)
                : Content.model([TextPart(e.text)]))
            .toList(),
      );

      final content = Content.text(text);
      var response = await chat.sendMessage(content);

      // invoke function call
      final functionCalls = response.functionCalls.toList();
      if (functionCalls.isNotEmpty) {
        final functionCall = functionCalls.first;
        final result = switch (functionCall.name) {
          'createTask' => await createTask(functionCall.args),
          _ => null
        };
        if (result != null) {
          response = await chat.sendMessage(
            Content.functionResponse(functionCall.name, result),
          );
        }
      }

      // add model message to list
      final modelMsg = (text: response.text?.trim() ?? '', isSender: false);
      setState(() {
        isLoading = false;
        messageList.insert(0, modelMsg);
      });

      // helper, rm later
      log('${chat.history.map((e) => e.toJson())}');
      log('${functionCalls.map((e) => e.toJson())}');
      log('$taskList');
    } catch (e) {
      setState(() => isLoading = false);
      showErrorSnackbar('$e');
    }
  }

  void showErrorSnackbar(String e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('My Assistant'),
        leading: const Padding(
          padding: EdgeInsets.all(8),
          child: CircleAvatar(
            foregroundImage: NetworkImage(
              profileImageUrl,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              reverse: true,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: messageList.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => i == 0
                  ? Visibility(
                      visible: isLoading,
                      child: BubbleNormal(
                        text: '...',
                        isSender: false,
                        bubbleRadius: 8,
                        color: Colors.grey.shade300,
                      ),
                    )
                  : BubbleNormal(
                      text: messageList[i - 1].text,
                      isSender: messageList[i - 1].isSender,
                      color: messageList[i - 1].isSender
                          ? Colors.amberAccent.shade100
                          : Colors.grey.shade300,
                      bubbleRadius: 8,
                    ),
            ),
          ),
          MessageBar(
            onSend: messageOnSend(),
            sendButtonColor: isLoading
                ? Theme.of(context).disabledColor
                : Theme.of(context).primaryColor,
            messageBarColor: Colors.white,
            messageBarHintText: 'Type your message...',
            messageBarHintStyle: TextStyle(
              color: Theme.of(context).disabledColor,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// TODO: update constants
const apiKey = '';
const systemInstruction = '''
  {
  }
  ''';
