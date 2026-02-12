import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:app_feijao/main.dart';

/// Splash screen widget displayed when the app starts
class SplashScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background image with cover fit
          Positioned.fill(
            child: Image.asset(
              'assets/imagens/feijao.png',
              fit: BoxFit.cover,
            ),
          ),

          // Blur and opacity overlay effect
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                // Semi-transparent white overlay with adjusted opacity
                color: const Color.fromARGB(213, 255, 255, 255)
                    .withOpacity(0.4),
              ),
            ),
          ),

          // Main content centered on screen
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App logo
                Image.asset(
                  'assets/imagens/logo_coen1.png',
                  width: 150,
                  height: 150,
                ),

                SizedBox(height: 20),

                // Welcome text
                Text(
                  "Welcome to L*a*b*",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown[900],
                  ),
                ),

                SizedBox(height: 40),

                // Start button that navigates to the main app
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (context) => ImagePredictorApp()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.brown[800],
                    padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    "Start",
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
