import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'questions.dart';
import 'navbar.dart';

class QuestionPage extends StatefulWidget {
  const QuestionPage({Key? key}) : super(key: key);

  @override
  State<QuestionPage> createState() => _QuestionPageState();
}

class _QuestionPageState extends State<QuestionPage> {
  late List<Question> questions;
  int currentQuestionIndex = 0;
  int score = 0;
  int? selectedOption;
  bool answered = false;
  bool testBitti = false;

  // Profil bilgileri
  String adSoyad = '';
  String yas = '';

  @override
  void initState() {
    super.initState();
    questions = getShuffledQuestions();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      adSoyad = prefs.getString('adSoyad') ?? 'Kullanıcı';
      yas = prefs.getString('yas') ?? '';
    });
  }

  void selectOption(int index) {
    if (answered || testBitti) return;
    setState(() {
      selectedOption = index;
      answered = true;
      if (index == questions[currentQuestionIndex].correctAnswerIndex) {
        score += 10;
      }
    });
  }

  void nextQuestion() {
    if (currentQuestionIndex < questions.length - 1) {
      setState(() {
        currentQuestionIndex++;
        selectedOption = null;
        answered = false;
      });
    } else {
      setState(() {
        testBitti = true;
        selectedOption = null;
        answered = false;
      });
    }
  }

  void restartTest() {
    setState(() {
      questions = getShuffledQuestions();
      currentQuestionIndex = 0;
      score = 0;
      selectedOption = null;
      answered = false;
      testBitti = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final question = questions[currentQuestionIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF6D6D6D),
      body: SafeArea(
        child: Center(
          child: Container(
            width: 320,
            margin: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF888888),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        adSoyad.isNotEmpty ? adSoyad : "Kullanıcı",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            "Test Başarınız : ",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 8,
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: score / 100,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF888888),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: testBitti
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Testi tamamladınız!",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "Puanınız: $score",
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 32),
                              IconButton(
                                icon: const Icon(Icons.refresh,
                                    size: 36, color: Colors.white),
                                tooltip: "Testi Yeniden Başlat",
                                onPressed: restartTest,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                "Tekrar çözmek için dönen oka tıklayın.",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                question.questionText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 18),
                              ...List.generate(question.options.length,
                                  (index) {
                                Color bgColor = const Color(0xFF5A5A5A);
                                Color textColor = Colors.white;
                                if (answered) {
                                  if (index == question.correctAnswerIndex) {
                                    bgColor = Colors.green;
                                    textColor = Colors.white;
                                  } else if (selectedOption == index) {
                                    bgColor = Colors.red;
                                    textColor = Colors.white;
                                  }
                                }
                                return GestureDetector(
                                  onTap: () => selectOption(index),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 14),
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: answered
                                                ? (index ==
                                                        question
                                                            .correctAnswerIndex
                                                    ? Colors.green
                                                    : (selectedOption == index
                                                        ? Colors.red
                                                        : const Color(
                                                            0xFF444444)))
                                                : const Color(0xFF444444),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          child: Center(
                                            child: Text(
                                              String.fromCharCode(65 + index),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            question.options[index],
                                            style: TextStyle(
                                              color: textColor,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                              const Spacer(),
                              if (answered)
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: nextQuestion,
                                    child: Text(
                                      currentQuestionIndex ==
                                              questions.length - 1
                                          ? 'Bitir'
                                          : 'Sonraki Soru',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const NavBar(
        selectedIndex: 0,
      ),
    );
  }
}
