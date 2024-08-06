import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'dart:async';
import 'package:logging/logging.dart';

final _logger = Logger('MyApp');

void main() {
  _setupLogging();
  runApp(const MyApp());
}

void _setupLogging() {
  Logger.root.level = Level.ALL; // Loga tudo, do mais detalhado ao mais crítico
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<List<Evento>> futureEvents;
  List<Evento> currentEvents = [];
  bool _isUpdating = false;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    futureEvents = fetchEvents();
  }

  void refreshEvents() {
    final now = DateTime.now();
    if (now.difference(_lastUpdate).inSeconds >= 30) {
      setState(() {
        _isUpdating = true;
        _lastUpdate = now;
        futureEvents = fetchEvents().then((events) {
          setState(() {
            currentEvents = events;
            _isUpdating = false;
          });
          return events;
        });
      });
    } else {
      // Simula uma atualização mostrando o indicador de carregamento temporário
      setState(() {
        _isUpdating = true;
      });

      Future.delayed(const Duration(seconds: 2), () {
        setState(() {
          _isUpdating = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agenda do Militante',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Agenda do Militante', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
        ),
        body: FutureBuilder<List<Evento>>(
          future: futureEvents,
          builder: (context, snapshot) {
            if (_isUpdating || snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Erro: ${snapshot.error}'));
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('Nenhum evento encontrado'));
            } else {
              var eventosPorData = agruparEventosPorData(snapshot.data!);
              return ListView(
                children: eventosPorData.entries.map((entry) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('dd/MM/yyyy').format(entry.key)),
                      ...entry.value.map((evento) {
                        return ListTile(
                          title: Text('${evento.titulo} - ${DateFormat.Hm().format(evento.data)}'),
                          subtitle: Text(evento.descricao),
                        );
                      }),
                    ],
                  );
                }).toList(),
              );
            }
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: refreshEvents,
          child: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}

Future<List<Evento>> fetchEvents() async {
  const calendarId = 'c3de1c8f61a43c212e13746e43f55c94e0a5311557d34eedcb3a7651226a7dc3@group.calendar.google.com';
  final apiKey = await rootBundle.loadString('config/calendar_key.txt');

  // Obtém a data de ontem
  var agora = DateTime.now();
  var ontem = DateTime(agora.year, agora.month, agora.day).subtract(const Duration(days: 1));

  // Converte a data para o formato ISO 8601
  var timeMin = ontem.toUtc().toIso8601String();

  final url = Uri.parse('https://www.googleapis.com/calendar/v3/calendars/$calendarId/events?key=$apiKey&timeMin=$timeMin');
  final response = await http.get(url);
  _logger.info('HTTP response status: ${response.statusCode}');

  if (response.statusCode == 200) {
    var data = json.decode(response.body);
    var items = data['items'] as List;
    List<Evento> eventos = items.map((item) {
      return Evento.fromJson(item);
    }).toList();

    // Filtra eventos a partir de ontem
    eventos = eventos.where((evento) => evento.data.isAfter(ontem)).toList();
    eventos.sort((a, b) => a.data.compareTo(b.data));

    return eventos;
  } else {
    throw Exception('Falha na requisição: ${response.statusCode} Resposta: ${response.body} Falha ao carregar eventos');
  }
}

Map<DateTime, List<Evento>> agruparEventosPorData(List<Evento> eventos) {
  Map<DateTime, List<Evento>> eventosPorData = {};
  for (var evento in eventos) {
    var dataEvento = DateTime(evento.data.year, evento.data.month, evento.data.day);
    if (eventosPorData.containsKey(dataEvento)) {
      eventosPorData[dataEvento]!.add(evento);
    } else {
      eventosPorData[dataEvento] = [evento];
    }
  }

  eventosPorData.forEach((data, eventosDoDia) {
    eventosDoDia.sort((a, b) => a.data.compareTo(b.data));
  });

  return eventosPorData;
}

class Evento {
  String titulo;
  String descricao;
  DateTime data;

  Evento({required this.titulo, required this.descricao, required this.data});

  factory Evento.fromJson(Map<String, dynamic> json) {
    tz.initializeTimeZones();
    var location = tz.getLocation('America/Sao_Paulo');
    DateTime utcDate = DateTime.parse(json['start']['dateTime'] ?? json['start']['date']);
    DateTime localDate = tz.TZDateTime.from(utcDate, location);

    return Evento(
      titulo: json['summary'] ?? 'Sem título',
      descricao: json['description'] ?? 'Sem descrição',
      data: localDate,
    );
  }
}
