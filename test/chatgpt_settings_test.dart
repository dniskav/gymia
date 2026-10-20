import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/ai_model_catalog.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/data/chatgpt_auth.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/ui/ai_settings.dart';

void main() {
  setUp(() { FlutterSecureStorage.setMockInitialValues({}); });
  const config = AiConfig(service:AiService.chatgpt,baseUrl:ChatGptAuth.resource,
    model:'qa-model',protocol:AiProtocol.responses,apiKey:'',chatGptClientId:'oaiapp_test');
  Future<void> seed() async {
    await ChatGptAuth.storage.write(key:'gymia.chatgpt.accounts.v1',value:jsonEncode({'oaiapp_test':{
      'client_id':'oaiapp_test','subject':'person','email':'qa@example.test',
      'access_token':'fixture-access','refresh_token':'fixture-refresh',
      'scopes':ChatGptAuth.planScopes.split(' '),
      'expires_at':DateTime.now().add(const Duration(hours:1)).toIso8601String(),
    }}));
    await const AiSettingsStore().save(config);
  }
  Future<void> show(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder,200,scrollable:find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }
  testWidgets('ChatGPT settings hide API key, load account models, verify and disconnect offline', (tester) async {
    await seed();
    final auth=ChatGptAuth(profileId:'local',transport:(_,__)async{throw const ChatGptFailure('connection');});
    final catalog=AiModelCatalog(chatGptAuth:auth,transport:(_,__)async=>{'models':[{'slug':'qa-model','display_name':'QA Model','visibility':'list'}]});
    final client=AiClient(chatGptAuth:auth,transport:(_,__,body)async{
      if(body['stream']!=true)throw StateError('OAuth requires streaming');
      return {'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':'Conectado'}]}]};
    });
    await tester.pumpWidget(MaterialApp(home:AiSettingsScreen(chatGptAuth:auth,catalog:catalog,client:client)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-api-key')),findsNothing);
    expect(find.text('Conectada · permiso de uso del plan concedido'),findsOneWidget);
    final verify=find.text('Probar conexión · usa mi plan ChatGPT');
    await show(tester,verify);await tester.tap(verify);await tester.pumpAndSettle();
    expect(await const AiSettingsStore().isVerified(config),true);
    final disconnect=find.byKey(const Key('chatgpt-disconnect'));
    await show(tester,disconnect);await tester.tap(disconnect);await tester.pumpAndSettle();
    expect((await auth.account('oaiapp_test')).connected,false);
    expect(await const AiSettingsStore().load(),null);
    final warning=find.textContaining('No se confirmó la revocación remota');
    await show(tester,warning);expect(warning,findsOneWidget);
  });
  testWidgets('an existing API provider remains available beside ChatGPT', (tester) async {
    const legacy=AiConfig(service:AiService.openai,baseUrl:ChatGptAuth.resource,
      model:'legacy',protocol:AiProtocol.responses,apiKey:'fixture-key');
    await const AiSettingsStore().save(legacy);
    await tester.pumpWidget(MaterialApp(home:AiSettingsScreen(catalog:AiModelCatalog(transport:(_,__)async=>{'data':[{'id':'legacy'}]}))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-api-key')),findsOneWidget);
    expect((await const AiSettingsStore().load())!.apiKey,'fixture-key');
    await tester.tap(find.byType(DropdownButtonFormField<AiService>));await tester.pumpAndSettle();
    expect(find.text('ChatGPT · usar mi plan'),findsWidgets);
  });
}
