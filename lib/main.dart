import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<List<Evento>> futureEvents;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    futureEvents = fetchEvents();
  }

  void refreshEvents() {
    if (!_isUpdating) {
      setState(() {
        futureEvents = fetchEvents();
        _isUpdating = true;
      });

      Timer(const Duration(seconds: 30), () {
        setState(() {
          _isUpdating = false;
        });
      });
    } else {
      setState(() {
        futureEvents = Future.delayed(const Duration(seconds: 2), () => []);
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
            if (snapshot.connectionState == ConnectionState.waiting) {
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
                      }).toList(),
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
  final calendarId = 'c3de1c8f61a43c212e13746e43f55c94e0a5311557d34eedcb3a7651226a7dc3@group.calendar.google.com';
  final apiKey = await rootBundle.loadString('config/calendar_key.txt');
  final url = Uri.parse('https://www.googleapis.com/calendar/v3/calendars/$calendarId/events?key=$apiKey');
  final response = await http.get(url);

  if (response.statusCode == 200) {
    var data = json.decode(response.body);
    var items = data['items'] as List;
    List<Evento> eventos = items.map((item) {
      return Evento.fromJson(item);
    }).toList();

    var agora = DateTime.now();
    var hojeInicio = DateTime(agora.year, agora.month, agora.day);
    var hojeFim = hojeInicio.add(Duration(days: 1)).subtract(Duration(seconds: 1));

    eventos = eventos.where((evento) =>
    evento.data.isAfter(hojeInicio.subtract(Duration(days: 1))) && evento.data.isBefore(hojeFim.add(Duration(days: 1)))).toList();
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
