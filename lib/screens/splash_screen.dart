import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController radarController;
  late AnimationController pulseController;
  late AnimationController floatController;
  late AnimationController textController;

  @override
  void initState() {
    super.initState();

    radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();

    Timer(const Duration(milliseconds: 2800), () {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    });
  }

  @override
  void dispose() {
    radarController.dispose();
    pulseController.dispose();
    floatController.dispose();
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final radarSize = math.min(size.width * 0.75, 320.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF081B3A), Color(0xFF0A2A5E), Color(0xFF1565C0)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: radarSize,
                height: radarSize,
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    radarController,
                    pulseController,
                    floatController,
                  ]),
                  builder: (context, child) {
                    final pulse = 1.0 + (pulseController.value * 0.08);

                    final floatY =
                        math.sin(floatController.value * math.pi) * 12;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: Size(radarSize, radarSize),
                          painter: SplashRadarPainter(
                            radarController.value * 2 * math.pi,
                          ),
                        ),

                        Container(
                          width: 180 * pulse,
                          height: 180 * pulse,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.cyanAccent.withOpacity(0.12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.cyanAccent.withOpacity(0.45),
                                blurRadius: 60,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                        ),

                        Transform.translate(
                          offset: Offset(0, floatY),
                          child: Image.asset('assets/logo.png', width: 140),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 30),

              FadeTransition(
                opacity: textController,
                child: const Text(
                  'LAN Share',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              FadeTransition(
                opacity: textController,
                child: const Text(
                  'Fast • Secure • Offline',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SplashRadarPainter extends CustomPainter {
  final double sweepAngle;

  SplashRadarPainter(this.sweepAngle);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final radius = size.width / 2;

    final ringPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, ringPaint);
    }

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle,
        endAngle: sweepAngle + 0.5,
        colors: [Colors.transparent, Colors.cyanAccent.withOpacity(0.55)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      sweepAngle,
      0.5,
      true,
      sweepPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
