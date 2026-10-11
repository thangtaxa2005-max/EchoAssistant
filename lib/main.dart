import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';

import 'core/ai_interpreter.dart';
import 'core/reminders.dart';
import 'core/theme.dart';
import 'core/vietnamese_parser.dart';
import 'data/app_database.dart';

final dbProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());
final reminderProvider = Provider<ReminderService>((ref) => throw UnimplementedError());
final aiProvider = Provider<AiInterpreter>((ref) => AiInterpreter());
final tasksProvider = StreamProvider<List<Task>>((ref) => ref.watch(dbProvider).watchTasks());
final messagesProvider = StreamProvider<List<ChatMessage>>(
    (ref) => ref.watch(dbProvider).watchMessages());
final chatProvider = StateNotifierProvider<ChatController, ChatState>((ref) =>
    ChatController(ref.read(dbProvider), ref.read(reminderProvider), ref.read(aiProvider)));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  final reminders = ReminderService(db);
  await reminders.initialize();
  await reminders.rescheduleAll();
  runApp(ProviderScope(
    overrides: [dbProvider.overrideWithValue(db), reminderProvider.overrideWithValue(reminders)],
    child: const EchoApp(),
  ));
}

class EchoApp extends StatelessWidget {
  const EchoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EchoAssistant',
        debugShowCheckedModeBanner: false,
        theme: echoTheme(),
        home: const HomeScreen(),
      );
}

class ChatState {
  const ChatState({this.draft, this.busy = false, this.error});
  final ParsedCommand? draft;
  final bool busy;
  final String? error;
}

class ChatController extends StateNotifier<ChatState> {
  ChatController(this.db, this.reminders, this.ai) : super(const ChatState());
  final AppDatabase db;
  final ReminderService reminders;
  final AiInterpreter ai;
  final parser = VietnameseParser();
  final ids = const Uuid();
  String? lastTaskId;

  Future<void> _say(String role, String body) => db.addMessage(ChatMessagesCompanion(
        id: Value(ids.v4()),
        role: Value(role),
        body: Value(body),
        createdAt: Value(DateTime.now().microsecondsSinceEpoch),
      ));

  Future<Task?> _recentTask() async {
    if (lastTaskId != null) {
      final task = await db.taskById(lastTaskId!);
      if (task != null) return task;
    }
    final pending = (await db.allTasks()).where((t) => t.status == 'pending').toList();
    if (pending.isEmpty) return null;
    pending.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return pending.first;
  }

  Future<void> send(String message) async {
    final input = message.trim();
    if (input.isEmpty || state.busy) return;
    state = ChatState(busy: true, draft: state.draft);
    try {
      await _say('user', input);
      final now = DateTime.now();
      if (RegExp(r'^(việc hôm nay|hôm nay có việc gì|xem việc hôm nay)[?.! ]*$', caseSensitive: false).hasMatch(input)) {
        final today = (await db.allTasks()).where((task) {
          final due = DateTime.fromMillisecondsSinceEpoch(task.dueAt);
          return task.status == 'pending' && due.year == now.year && due.month == now.month && due.day == now.day;
        }).toList();
        await _say('assistant', today.isEmpty
            ? 'Hôm nay chưa có việc nào đang chờ.'
            : today.map((task) => '${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(task.dueAt))} · ${task.title}').join('\n'));
        state = const ChatState();
        return;
      }
      var parsed = parser.parse(input, now: now);
      final obvious = parsed.dueAt != null && parsed.title != null;
      if (!obvious && parsed.kind == CommandKind.create) {
        final fromAi = await ai.interpret(input, now);
        if (fromAi != null && fromAi.kind != CommandKind.unknown) parsed = fromAi;
      }
      if (parsed.kind == CommandKind.delete || parsed.kind == CommandKind.complete) {
        final task = await _recentTask();
        if (task == null) {
          await _say('assistant', 'Mình chưa thấy việc nào để sửa. Cậu mở danh sách việc thử nhé.');
        } else if (!parsed.refersToPrevious && parsed.title != null &&
            !task.title.toLowerCase().contains(parsed.title!.toLowerCase())) {
          await _say('assistant', 'Mình chưa chắc cậu muốn sửa việc nào. Hãy chọn việc trong danh sách nhé.');
        } else if (parsed.kind == CommandKind.delete) {
          await db.removeTask(task.id);
          await reminders.cancel(task.id);
          await _say('assistant', 'Đã xóa “${task.title}” rồi nhé.');
        } else {
          await reminders.applyAction(task, 'done');
          await _say('assistant', 'Tuyệt, đã đánh dấu xong “${task.title}”.');
        }
        state = const ChatState();
        return;
      }
      if (parsed.kind == CommandKind.move) {
        final task = await _recentTask();
        if (task == null) {
          await _say('assistant', 'Mình chưa thấy việc nào để dời.');
        } else if (parsed.dueAt == null) {
          await _say('assistant', 'Cậu muốn dời “${task.title}” đến mấy giờ?');
          state = ChatState(draft: ParsedCommand(
            kind: CommandKind.move,
            title: task.title,
            refersToPrevious: true,
          ));
          return;
        } else {
          await _updateTask(task, parsed.dueAt!);
          await _say('assistant', 'Đã dời “${task.title}” sang ${_formatDate(parsed.dueAt!)}.');
        }
        state = const ChatState();
        return;
      }
      if (state.draft != null && parsed.dueAt != null &&
          (parsed.title == null || parsed.title!.length < 5)) {
        final pending = state.draft!;
        if (pending.kind == CommandKind.move) {
          final task = await _recentTask();
          if (task != null) {
            await _updateTask(task, parsed.dueAt!);
            await _say('assistant', 'Đã dời “${task.title}” sang ${_formatDate(parsed.dueAt!)}.');
          }
          state = const ChatState();
          return;
        }
        parsed = ParsedCommand(
          kind: CommandKind.create,
          title: pending.title,
          dueAt: parsed.dueAt,
          durationMinutes: pending.durationMinutes,
          recurrence: pending.recurrence,
        );
      }
      if (parsed.title == null) {
        await _say('assistant', 'Cậu muốn mình nhắc việc gì? Ví dụ: “8h tối mai học từ vựng 30 phút”.');
        state = const ChatState();
      } else if (parsed.dueAt == null) {
        await _say('assistant', 'Mình sẽ nhắc “${parsed.title}”. Cậu muốn nhắc lúc mấy giờ?');
        state = ChatState(draft: parsed);
      } else if (!parsed.dueAt!.isAfter(now)) {
        await _say('assistant', 'Giờ này đã qua rồi. Cậu chọn giờ khác giúp mình nhé.');
        state = ChatState(draft: ParsedCommand(
          kind: CommandKind.create,
          title: parsed.title,
          durationMinutes: parsed.durationMinutes,
          recurrence: parsed.recurrence,
        ));
      } else {
        await _say('assistant', 'Mình đặt nhắc nhé?');
        state = ChatState(draft: parsed);
      }
    } catch (e) {
      state = ChatState(error: 'Có lỗi khi xử lý tin nhắn. Cậu thử lại nhé.');
    } finally {
      if (state.busy) state = ChatState(draft: state.draft, error: state.error);
    }
  }

  Future<void> _updateTask(Task task, DateTime newDue) async {
    await db.saveTask(TasksCompanion(
      id: Value(task.id),
      title: Value(task.title),
      dueAt: Value(newDue.millisecondsSinceEpoch),
      durationMinutes: Value(task.durationMinutes),
      recurrence: Value(task.recurrence),
      status: const Value('pending'),
      originText: Value(task.originText),
      createdAt: Value(task.createdAt),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
    final updated = await db.taskById(task.id);
    if (updated != null) await reminders.schedule(updated);
  }

  Future<void> confirm() async {
    final draft = state.draft;
    if (draft?.title == null || draft?.dueAt == null) return;
    state = const ChatState(busy: true);
    try {
      final id = ids.v4();
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.saveTask(TasksCompanion(
        id: Value(id),
        title: Value(draft!.title!),
        dueAt: Value(draft.dueAt!.millisecondsSinceEpoch),
        durationMinutes: Value(draft.durationMinutes),
        recurrence: Value(draft.recurrence),
        status: const Value('pending'),
        originText: Value(draft.title!),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      lastTaskId = id;
      final task = await db.taskById(id);
      if (task != null) await reminders.schedule(task);
      await _say('assistant', 'Đã đặt nhắc “${draft.title}” lúc ${_formatDate(draft.dueAt!)}. Mình sẽ giục lại sau 10 phút nếu cậu chưa xử lý.');
      state = const ChatState();
    } catch (_) {
      state = ChatState(draft: draft, error: 'Chưa đặt được lời nhắc. Hãy thử lại.');
    }
  }

  void discard() => state = const ChatState();
}

String _formatDate(DateTime date) => DateFormat('HH:mm · dd/MM/yyyy').format(date);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int page = 0;

  @override
  Widget build(BuildContext context) {
    final body = [const ChatPage(), const TaskPage(), const SettingsPage()][page];
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (value) => setState(() => page = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Trò chuyện'),
          NavigationDestination(icon: Icon(Icons.checklist_rounded), label: 'Việc của tôi'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Cài đặt'),
        ],
      ),
    );
  }
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final speech = SpeechToText();
  bool listening = false;

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _mic() async {
    if (listening) {
      await speech.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    try {
      final ready = await speech.initialize(onError: (_) {
        if (!mounted) return;
        setState(() => listening = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nhận dạng giọng nói chưa sẵn sàng. Hãy kiểm tra quyền micro và cài gói tiếng Việt ngoại tuyến.'),
        ));
      });
      if (!ready) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máy chưa cho phép nhận giọng nói. Hãy kiểm tra quyền micro.')));
        return;
      }
      if (!mounted) return;
      setState(() => listening = true);
      await speech.listen(
        listenOptions: SpeechListenOptions(localeId: 'vi_VN', onDevice: true),
        onResult: (result) {
          input.text = result.recognizedWords;
          input.selection = TextSelection.collapsed(offset: input.text.length);
          if (result.finalResult && mounted) setState(() => listening = false);
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => listening = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Không mở được micro ngoại tuyến. Hãy cài gói tiếng Việt trên điện thoại.'),
      ));
    }
  }

  void _send() {
    final value = input.text;
    input.clear();
    FocusScope.of(context).unfocus();
    ref.read(chatProvider.notifier).send(value);
    Future.delayed(const Duration(milliseconds: 250), () {
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider).valueOrNull ?? [];
    final chat = ref.watch(chatProvider);
    return Column(children: [
      const _PageHeader(title: 'Echo', subtitle: 'Trợ lý của bạn · sẵn sàng'),
      Expanded(
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          children: [
            if (messages.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: _Bubble(text: 'Chào cậu! Hôm nay mình giúp gì được? Thử nhắn “8h tối nay nhắc tớ học từ vựng 30p” nhé.', mine: false),
              ),
            for (final message in messages)
              _Bubble(text: message.body, mine: message.role == 'user'),
            if (chat.draft?.dueAt != null && chat.draft?.title != null)
              _DraftCard(command: chat.draft!),
            if (chat.error != null)
              Padding(padding: const EdgeInsets.all(8), child: Text(chat.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (chat.busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, children: [
            ActionChip(label: const Text('Việc hôm nay'), onPressed: () => ref.read(chatProvider.notifier).send('Việc hôm nay')),
            ActionChip(label: const Text('Dời việc đó sang mai'), onPressed: () => ref.read(chatProvider.notifier).send('Dời việc đó sang mai 8h sáng')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(
              controller: input,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(hintText: 'Nhắn hoặc nói với Echo...', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 11)),
            )),
            const SizedBox(width: 7),
            IconButton.filledTonal(onPressed: _mic, icon: Icon(listening ? Icons.stop : Icons.mic_none), tooltip: listening ? 'Dừng nghe' : 'Nói tiếng Việt'),
            IconButton.filled(onPressed: chat.busy ? null : _send, icon: const Icon(Icons.arrow_upward), tooltip: 'Gửi'),
          ]),
        ]),
      ),
    ]);
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: EchoColors.soft, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.waves_rounded, color: EchoColors.teal)),
          const SizedBox(width: 11),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: EchoColors.ink)),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6B8481))),
          ]),
        ]),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine});
  final String text;
  final bool mine;
  @override
  Widget build(BuildContext context) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: mine ? EchoColors.teal : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(text, style: TextStyle(color: mine ? Colors.white : EchoColors.ink, height: 1.3)),
          ),
        ),
      );
}

class _DraftCard extends ConsumerWidget {
  const _DraftCard({required this.command});
  final ParsedCommand command;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 310,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('XÁC NHẬN LỜI NHẮC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: EchoColors.teal, letterSpacing: .8)),
            const SizedBox(height: 7),
            Text(command.title!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(_formatDate(command.dueAt!), style: const TextStyle(color: Color(0xFF55716D))),
            if (command.durationMinutes > 0) Text('${command.durationMinutes} phút'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: FilledButton(onPressed: () => ref.read(chatProvider.notifier).confirm(), child: const Text('Đặt nhắc'))),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => ref.read(chatProvider.notifier).discard(), child: const Text('Bỏ')),
            ]),
          ]),
        ),
      );
}

class TaskPage extends ConsumerWidget {
  const TaskPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider).valueOrNull ?? [];
    final now = DateTime.now();
    final pending = tasks.where((t) => t.status == 'pending').toList();
    final done = tasks.where((t) => t.status != 'pending').toList();
    return Column(children: [
      _PageHeader(title: 'Hôm nay', subtitle: DateFormat('dd/MM/yyyy').format(now)),
      Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: EchoColors.soft, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('NHỊP CỦA HÔM NAY', style: TextStyle(color: EchoColors.teal, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: .8)),
            const SizedBox(height: 5),
            Text(pending.isEmpty ? 'Bạn đã xử lý hết việc rồi!' : 'Bạn có ${pending.length} việc đang chờ.', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 18),
        const Text('Sắp tới', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 7),
        if (pending.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Chưa có việc nào. Hãy nhắn Echo để đặt nhắc.')),
        for (final task in pending) _TaskTile(task: task),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Đã xử lý', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          for (final task in done) _TaskTile(task: task),
        ],
      ])),
    ]);
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});
  final Task task;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateTime.fromMillisecondsSinceEpoch(task.dueAt);
    return Card(child: Padding(
      padding: const EdgeInsets.all(11),
      child: Row(children: [
        SizedBox(width: 64, child: Text(DateFormat('HH:mm').format(date), style: const TextStyle(color: EchoColors.teal, fontWeight: FontWeight.w800))),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(task.title, style: TextStyle(fontWeight: FontWeight.w700, decoration: task.status == 'done' ? TextDecoration.lineThrough : null)),
          Text('${DateFormat('dd/MM').format(date)}${task.durationMinutes > 0 ? ' · ${task.durationMinutes} phút' : ''}${task.recurrence != 'none' ? ' · lặp ${task.recurrence == 'daily' ? 'mỗi ngày' : 'mỗi tuần'}' : ''}',
              style: const TextStyle(color: Color(0xFF6D8581), fontSize: 12)),
        ])),
        PopupMenuButton<String>(
          tooltip: 'Tùy chọn việc',
          onSelected: (action) async {
            if (action == 'delete') {
              await ref.read(dbProvider).removeTask(task.id);
              await ref.read(reminderProvider).cancel(task.id);
            } else {
              await ref.read(reminderProvider).applyAction(task, action);
            }
          },
          itemBuilder: (context) => [
            if (task.status == 'pending') ...[
              const PopupMenuItem(value: 'done', child: Text('Xong')),
              const PopupMenuItem(value: 'snooze', child: Text('Lùi 15 phút')),
              const PopupMenuItem(value: 'skip', child: Text('Bỏ lần này')),
            ],
            const PopupMenuItem(value: 'delete', child: Text('Xóa việc')),
          ],
        ),
      ]),
    ));
  }
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final gemini = TextEditingController();
  final groq = TextEditingController();
  bool saved = false;

  @override
  void initState() {
    super.initState();
    ref.read(aiProvider).loadKeys().then((keys) {
      if (mounted) setState(() { gemini.text = keys.$1; groq.text = keys.$2; });
    });
  }

  @override
  void dispose() { gemini.dispose(); groq.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    const _PageHeader(title: 'Cài đặt', subtitle: 'Dữ liệu ở trên máy của bạn'),
    const SizedBox(height: 12),
    const Text('Khóa AI tùy chọn', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
    const SizedBox(height: 5),
    const Text('Echo hiểu các câu nhắc thông dụng ngay trên máy. Khóa AI giúp hiểu cách nói phức tạp hơn. Khóa được lưu trong vùng bảo mật của thiết bị.'),
    const SizedBox(height: 18),
    TextField(controller: gemini, obscureText: true, decoration: const InputDecoration(labelText: 'Gemini API key')),
    const SizedBox(height: 12),
    TextField(controller: groq, obscureText: true, decoration: const InputDecoration(labelText: 'Groq API key (dự phòng)')),
    const SizedBox(height: 14),
    FilledButton(onPressed: () async {
      await ref.read(aiProvider).saveKeys(gemini: gemini.text, groq: groq.text);
      if (mounted) setState(() => saved = true);
    }, child: Text(saved ? 'Đã lưu' : 'Lưu khóa')),
    const SizedBox(height: 25),
    const Text('Để nhắc đúng giờ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
    const SizedBox(height: 6),
    const Text('Cho phép thông báo và “Báo thức & lời nhắc” cho Echo trong Cài đặt Android. Nếu máy chặn hoạt động nền, hãy bỏ tối ưu pin cho Echo. Độ chính xác phụ thuộc quyền báo thức của máy.'),
    const SizedBox(height: 20),
    OutlinedButton.icon(
      onPressed: () => ref.read(reminderProvider).initialize(),
      icon: const Icon(Icons.notifications_active_outlined),
      label: const Text('Xin lại quyền thông báo'),
    ),
  ]);
}
