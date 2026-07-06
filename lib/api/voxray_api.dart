// lib/api/voxray_api.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class VoxrayApi {
  static const String baseUrl = 'https://donkelleymusic--voxray-pro-api-api.modal.run';

  static Future<Map<String, dynamic>> analyzeAdvanced({
    required Uint8List audioBytes,
    required String filename,
    required String uploadType,
    required String stemTarget,
    required List<String> instruments,
    bool isTestMode = false,
  }) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/analyze-advanced'))
      ..fields['upload_type'] = uploadType
      ..fields['stem_target'] = stemTarget
      ..fields['instruments_json'] = jsonEncode(instruments);
      
    if (isTestMode) {
      request.fields['is_test_mode'] = 'true';
    }
    
    request.files.add(http.MultipartFile.fromBytes('file', audioBytes, filename: filename));
    
    var response = await request.send();
    if (response.statusCode != 200) {
      throw Exception("Server rejected file upload (Status: ${response.statusCode})");
    }
    return jsonDecode(await response.stream.bytesToString());
  }

  static Future<Map<String, dynamic>> getTaskStatus(String jobId) async {
    var res = await http.get(Uri.parse('$baseUrl/get-task-status?task_id=$jobId'));
    if (res.statusCode == 404) throw Exception('Task expired or crashed on server');
    if (res.statusCode != 200) throw Exception('Server returned ${res.statusCode}');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> generateStemOnDemand({
    required String taskId,
    required String targetStem,
  }) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/generate-stem-on-demand'))
      ..fields['task_id'] = taskId
      ..fields['target_stem'] = targetStem;
      
    var res = await request.send();
    if (res.statusCode != 200) throw Exception("Server returned status code ${res.statusCode}");
    return jsonDecode(await res.stream.bytesToString());
  }

  static Future<Map<String, dynamic>> analyzeXray({
    required String taskId,
    required List<Map<String, dynamic>> enrichedNotes,
  }) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/analyze-xray'))
      ..fields['task_id'] = taskId
      ..fields['notes_manifest'] = jsonEncode(enrichedNotes);
      
    var response = await request.send();
    var responseData = await http.Response.fromStream(response);
    if (responseData.statusCode != 200) throw Exception("X-Ray connection error");
    return jsonDecode(responseData.body);
  }

  static Future<Uint8List> fetchStemBytes(String taskId, String stemName) async {
    final res = await http.get(Uri.parse('$baseUrl/api/stem/$taskId/$stemName?format=ogg'));
    if (res.statusCode != 200) throw Exception("Stem fetch error ${res.statusCode}");
    return res.bodyBytes;
  }

  static Future<Map<String, dynamic>> batchRenderAndMix({
    required String taskId,
    required Uint8List audioBytes,
    required Map<String, dynamic> editManifest,
    bool isTestMode = false,
    String? exportFormat,
  }) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/batch-render-and-mix'))
      ..fields['task_id'] = taskId
      ..fields['edit_manifest'] = jsonEncode(editManifest);
      
    if (isTestMode) request.fields['is_test_mode'] = 'true';
    if (exportFormat != null) request.fields['export_format'] = exportFormat;
    
    request.files.add(http.MultipartFile.fromBytes('file', audioBytes, filename: 'audio.wav'));
    
    var response = await request.send();
    var responseData = await http.Response.fromStream(response);
    if (responseData.statusCode != 200) {
      throw Exception("Server error ${responseData.statusCode}: ${responseData.body}");
    }
    return jsonDecode(responseData.body);
  }

  static Future<Map<String, dynamic>> generateDossier({
    required String taskId,
    required List<Map<String, dynamic>> enrichedNotes,
    required Map<String, dynamic> sessionMeta,
  }) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/generate-dossier'))
      ..fields['task_id'] = taskId
      ..fields['notes_manifest'] = jsonEncode(enrichedNotes)
      ..fields['session_meta'] = jsonEncode(sessionMeta);
      
    var response = await request.send();
    var responseData = await http.Response.fromStream(response);
    if (responseData.statusCode != 200) throw Exception("Server error ${responseData.statusCode}");
    return jsonDecode(responseData.body);
  }

  static Future<Map<String, dynamic>> generatePitchPrint({
    required String taskId,
    required List<Map<String, dynamic>> enrichedNotes,
    required bool fullSong,
    required double visibleStart,
    required double visibleEnd,
    required double songDuration,
  }) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/generate-pitchprint'))
      ..fields['task_id'] = taskId
      ..fields['notes_manifest'] = jsonEncode(enrichedNotes)
      ..fields['full_song'] = fullSong.toString()
      ..fields['visible_start'] = visibleStart.toString()
      ..fields['visible_end'] = visibleEnd.toString()
      ..fields['song_duration'] = songDuration.toString();
      
    var response = await request.send();
    var responseData = await http.Response.fromStream(response);
    if (responseData.statusCode != 200) throw Exception("Server error ${responseData.statusCode}");
    return jsonDecode(responseData.body);
  }

  static Future<Map<String, dynamic>> renderSnippet({
    required String taskId,
    required String stemName,
    required Map<String, dynamic> editData,
  }) async {
    var response = await http.post(
      Uri.parse('$baseUrl/render-snippet'),
      body: {
        'task_id': taskId,
        'stem_name': stemName,
        'edit_data': jsonEncode(editData)
      }
    );
    if (response.statusCode != 200) throw Exception("Snippet generation failed");
    return jsonDecode(response.body);
  }
}