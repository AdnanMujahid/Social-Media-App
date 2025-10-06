import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Import for date formatting
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/services.dart';

// NOTE: You must initialize Firebase in your main function before running the app.
// If you are using flutterfire, your main function setup might look something like this:
//
// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await Firebase.initializeApp(
//     options: DefaultFirebaseOptions.currentPlatform, // Use your generated options
//   );
//   runApp(const MyApp());
// }

// --- 1. DATA MODEL (POST) ---

/// Represents a single social media post.
class Post {
  final String id;
  final String userId;
  final String userName; // To display who made the post
  final String text;
  final Timestamp timestamp;
  final List<String> likes; // List of user IDs who liked the post
  final List<Comment> comments; // List of comments on the post
  final int shareCount; // Number of times the post was shared

  Post({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    required this.timestamp,
    this.likes = const [],
    this.comments = const [],
    this.shareCount = 0,
  });

  /// Factory constructor to create a Post from a Firestore document.
  factory Post.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Convert comments from Firestore
    List<Comment> commentsList = [];
    if (data['comments'] != null) {
      commentsList = List<Map<String, dynamic>>.from(data['comments'])
          .map((commentData) => Comment.fromMap(commentData))
          .toList();
    }
    
    return Post(
      id: doc.id,
      userId: data['userId'] ?? 'Unknown',
      userName: data['userName'] ?? 'User',
      text: data['text'] ?? 'No content',
      timestamp: data['timestamp'] ?? Timestamp.now(),
      likes: List<String>.from(data['likes'] ?? []),
      comments: commentsList,
      shareCount: data['shareCount'] ?? 0,
    );
  }
  
  /// Check if a user has liked this post
  bool isLikedBy(String userId) {
    return likes.contains(userId);
  }
  
  /// Create a map for Firestore updates
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'text': text,
      'timestamp': timestamp,
      'likes': likes,
      'comments': comments.map((comment) => comment.toMap()).toList(),
      'shareCount': shareCount,
    };
  }
}

/// Represents a comment on a post
class Comment {
  final String id;
  final String userId;
  final String userName;
  final String text;
  final Timestamp timestamp;

  Comment({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    required this.timestamp,
  });

  factory Comment.fromMap(Map<String, dynamic> data) {
    return Comment(
      id: data['id'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      text: data['text'] ?? '',
      timestamp: data['timestamp'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'text': text,
      'timestamp': timestamp,
    };
  }
}

// --- 2. FIREBASE SERVICE ---

/// Handles all interactions with Firestore and Firebase Auth.
class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get the current user's email or fall back to an empty string.
  String get currentUserEmail => _auth.currentUser?.email ?? '';

  // Get the current user's UID or fall back to an empty string.
  String get currentUserId => _auth.currentUser?.uid ?? '';

  /// Stream of all posts, ordered by timestamp (newest first).
  Stream<List<Post>> get postsStream {
    return _db
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => Post.fromFirestore(doc)).toList());
  }

  /// Adds a new post to the 'posts' collection.
  Future<void> addPost(String content) async {
    if (_auth.currentUser == null) {
      throw Exception("User is not logged in.");
    }

    // You might want a dedicated 'users' collection to fetch the display name,
    // but for simplicity, we use the first part of the email as a basic username.
    final userName = _auth.currentUser!.email!.split('@').first;

    await _db.collection('posts').add({
      'userId': _auth.currentUser!.uid,
      'userName': userName,
      'text': content,
      'timestamp': FieldValue.serverTimestamp(),
      'likes': [],
      'comments': [],
      'shareCount': 0,
    });
  }
  
  /// Toggles a like on a post.
  Future<void> toggleLike(String postId) async {
    if (_auth.currentUser == null) {
      throw Exception("User is not logged in.");
    }
    
    final userId = _auth.currentUser!.uid;
    final postRef = _db.collection('posts').doc(postId);
    
    return _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(postRef);
      if (!snapshot.exists) {
        throw Exception("Post does not exist!");
      }
      
      final post = Post.fromFirestore(snapshot);
      
      if (post.isLikedBy(userId)) {
        // Unlike the post
        transaction.update(postRef, {
          'likes': FieldValue.arrayRemove([userId])
        });
      } else {
        // Like the post
        transaction.update(postRef, {
          'likes': FieldValue.arrayUnion([userId])
        });
      }
    });
  }
  
  /// Adds a comment to a post.
  Future<void> addComment(String postId, String commentText) async {
    if (_auth.currentUser == null) {
      throw Exception("User is not logged in.");
    }
    
    final userId = _auth.currentUser!.uid;
    final userName = _auth.currentUser!.email!.split('@').first;
    
    final comment = Comment(
      userId: userId,
      userName: userName,
      text: commentText,
      timestamp: Timestamp.now(), id: userId,
    );
    
    await _db.collection('posts').doc(postId).update({
      'comments': FieldValue.arrayUnion([comment.toMap()])
    });
  }
  
  /// Increments the share count for a post.
  Future<void> incrementShareCount(String postId) async {
    await _db.collection('posts').doc(postId).update({
      'shareCount': FieldValue.increment(1)
    });
  }

  /// Logs out the current user.
  Future<void> signOut() => _auth.signOut();
}

// --- 3. MAIN APPLICATION & AUTH ROUTING ---

void main() async {
  // NOTE: REPLACE THIS WITH YOUR ACTUAL FIREBASE INITIALIZATION LOGIC
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Assuming default Firebase setup
  // END NOTE

  runApp(const MyApp());
}

// Custom page route for smooth transitions
class FadePageRoute<T> extends PageRoute<T> {
  final Widget child;
  
  FadePageRoute({required this.child})
      : super(fullscreenDialog: false);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return FadeTransition(
      opacity: animation,
      child: child,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MaterialApp(
          title: 'Social Connect',
          debugShowCheckedModeBanner: false,
          onGenerateRoute: (settings) {
            if (settings.name == '/home') {
              return FadePageRoute(child: const HomePage());
            } else if (settings.name == '/login') {
              return FadePageRoute(child: const LoginPage());
            }
            return null;
          },
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6A5AE0),
              brightness: Brightness.light,
              primary: const Color(0xFF6A5AE0),
              secondary: const Color(0xFFFF8A65),
              tertiary: const Color(0xFF26A69A),
              background: const Color(0xFFF8F9FE),
              surface: Colors.white,
            ),
            fontFamily: 'Poppins',
            textTheme: const TextTheme(
              displayLarge: TextStyle(fontWeight: FontWeight.bold),
              displayMedium: TextStyle(fontWeight: FontWeight.bold),
              displaySmall: TextStyle(fontWeight: FontWeight.bold),
              headlineMedium: TextStyle(fontWeight: FontWeight.w700),
              titleLarge: TextStyle(fontWeight: FontWeight.w600),
              titleMedium: TextStyle(fontWeight: FontWeight.w600),
              bodyLarge: TextStyle(fontSize: 16.0),
              bodyMedium: TextStyle(fontSize: 14.0),
            ),
            scaffoldBackgroundColor: const Color(0xFFF8F9FE),
            appBarTheme: const AppBarTheme(
              elevation: 0,
              centerTitle: true,
              backgroundColor: Colors.transparent,
              foregroundColor: Color(0xFF6A5AE0),
              titleTextStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Color(0xFF6A5AE0),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                backgroundColor: const Color(0xFF6A5AE0),
                foregroundColor: Colors.white,
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF6A5AE0), width: 2),
              ),
              contentPadding: const EdgeInsets.all(20),
              hintStyle: TextStyle(color: Colors.grey[400]),
            ),
            cardColor: Colors.white,
            cardTheme: CardTheme.of(context).copyWith(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6A5AE0),
              brightness: Brightness.dark,
              primary: const Color(0xFF6A5AE0),
              secondary: const Color(0xFFFF8A65),
              tertiary: const Color(0xFF26A69A),
              background: const Color(0xFF121212),
              surface: const Color(0xFF1E1E1E),
            ),
            fontFamily: 'Poppins',
            scaffoldBackgroundColor: const Color(0xFF121212),
            appBarTheme: const AppBarTheme(
              elevation: 0,
              centerTitle: true,
              backgroundColor: Colors.transparent,
              foregroundColor: Color(0xFF6A5AE0),
              titleTextStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Color(0xFF6A5AE0),
              ),
            ),
          ),
          builder: (context, child) {
            // Apply responsive font scaling
            final mediaQuery = MediaQuery.of(context);
            final scale = mediaQuery.size.width / 375; // Base design width
            final scaleFactor = scale.clamp(0.8, 1.2); // Limit scaling range
            
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaleFactor: scaleFactor,
              ),
              child: child!,
            );
          },
          themeMode: ThemeMode.light,
          home: const AuthWrapper(),
        );
      },
    );
  }
}

/// A wrapper widget that listens to Firebase Auth state changes
/// and redirects the user to the correct page (Login or Home).
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 1500),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: 0.5 + (value * 0.5),
                    child: Opacity(
                      opacity: value,
                      child: child,
                    ),
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_alt_rounded,
                      size: 80,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Social Connect',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 32),
                    CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        // If the user is logged in, show the HomePage
        if (snapshot.hasData && snapshot.data != null) {
          return const HomePage();
        }
        // Otherwise, show the LoginPage
        return const LoginPage();
      },
    );
  }
}

// --- 4. AUTHENTICATION PAGES (Login/Register) ---

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLogin = true;
  String? _errorMessage;
  bool _isLoading = false;

  Future<void> _submitAuthForm() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_isLogin ? 'Login' : 'Register'),
          backgroundColor: Colors.blueGrey[700]),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Email Input
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Password Input
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              // Submit Button
              if (_isLoading)
                const CircularProgressIndicator()
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitAuthForm,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.blueGrey[500],
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_isLogin ? 'Sign In' : 'Sign Up',
                        style: const TextStyle(fontSize: 18)),
                  ),
                ),
              const SizedBox(height: 20),
              // Error Message
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 10),
              // Toggle Button
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                    _errorMessage = null; // Clear error on switch
                  });
                },
                child: Text(_isLogin
                    ? 'Need an account? Register'
                    : 'Already have an account? Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- 5. HOME PAGE (FEED & NAVIGATION) ---

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final FirebaseService _service = FirebaseService();

  // The screens accessible via the bottom navigation bar
  late final List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    _widgetOptions = <Widget>[
      FeedScreen(service: _service), // Index 0: Main Feed
      ProfilePage(service: _service), // Index 1: Profile
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  /// Shows a modal for the user to create a new post.
  void _showCreatePostDialog() {
    final TextEditingController postController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                      child: Icon(
                        Icons.person,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create Post',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Share your thoughts',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: postController,
                  autofocus: true,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: 'What\'s on your mind?',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.photo_outlined,
                            color: theme.colorScheme.secondary,
                          ),
                          onPressed: () {
                            // TODO: Implement photo upload
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.emoji_emotions_outlined,
                            color: theme.colorScheme.tertiary,
                          ),
                          onPressed: () {
                            // TODO: Implement emoji picker
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            if (postController.text.trim().isNotEmpty) {
                              await _service.addPost(postController.text.trim());
                              Navigator.of(context).pop();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: const Text('Post'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_alt_rounded,
              color: theme.colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(
              'Social Connect',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              Icons.notifications_outlined,
              color: theme.colorScheme.primary,
            ),
            onPressed: () {
              // TODO: Implement notifications
            },
          ),
          IconButton(
            icon: Icon(
              Icons.search,
              color: theme.colorScheme.primary,
            ),
            onPressed: () {
              // TODO: Implement search
            },
          ),
          const SizedBox(width: 8),
        ],
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.background,
              theme.colorScheme.background,
              theme.colorScheme.primary.withOpacity(0.05),
            ],
          ),
        ),
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      floatingActionButton: _selectedIndex == 0
          ? Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: FloatingActionButton(
                onPressed: _showCreatePostDialog,
                elevation: 0,
                backgroundColor: Colors.transparent,
                child: const Icon(Icons.add, color: Colors.white),
              ),
            )
          : null, // Only show FAB on the Feed screen
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          child: BottomAppBar(
            notchMargin: 8,
            shape: const CircularNotchedRectangle(),
            color: Colors.white,
            elevation: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, 'Feed'),
                const SizedBox(width: 40),
                _buildNavItem(1, Icons.person_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildNavItem(int index, IconData icon, String label) {
    final theme = Theme.of(context);
    final isSelected = _selectedIndex == index;
    
    return InkWell(
      onTap: () => _onItemTapped(index),
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SizedBox(
          height: 32.0, // Fixed height to match constraint
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 16.0, // Constrain icon height
                child: Icon(
                  icon,
                  color: isSelected 
                    ? theme.colorScheme.primary 
                    : theme.colorScheme.onSurface.withOpacity(0.6),
                  size: isSelected ? 16 : 14, // Reduced size
                ),
              ),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 10, // Reduced font size
                  ),
                ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// --- 6. FEED SCREEN ---

class FeedScreen extends StatelessWidget {
  final FirebaseService service;
  const FeedScreen({required this.service, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return StreamBuilder<List<Post>>(
      stream: service.postsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Error: ${snapshot.error}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading posts...',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          );
        }

        final posts = snapshot.data ?? [];

        if (posts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.post_add,
                  size: 64,
                  color: theme.colorScheme.primary.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No posts yet',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onBackground,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Be the first to share something!',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onBackground.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    // This will trigger the FAB action
                    if (context.findAncestorStateOfType<_HomePageState>() != null) {
                      context.findAncestorStateOfType<_HomePageState>()!._showCreatePostDialog();
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Create Post'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 80),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            // Add staggered animation for each post card
            return TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 300 + (index * 50)),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 0,
                      child: _buildPostContent(context, post),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
  
  Widget _buildPostContent(BuildContext context, Post post) {
    final theme = Theme.of(context);
    
    // Generate a consistent color based on the username
    final usernameHash = post.userName.hashCode;
    final avatarColors = [
      theme.colorScheme.primary.withOpacity(0.8),
      theme.colorScheme.secondary.withOpacity(0.8),
      theme.colorScheme.tertiary.withOpacity(0.8),
      Color(0xFF9C27B0).withOpacity(0.8), // Purple
      Color(0xFF009688).withOpacity(0.8), // Teal
    ];
    final avatarColor = avatarColors[usernameHash % avatarColors.length];
    
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 500),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: child,
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: avatarColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    backgroundColor: avatarColor,
                    child: Text(
                      post.userName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.userName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      DateFormat.yMMMd().add_jm().format(
                            post.timestamp.toDate(),
                          ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.more_horiz,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
                onPressed: () {
                  // TODO: Implement post options menu
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            post.text,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Divider(
            color: theme.colorScheme.onSurface.withOpacity(0.1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildPostAction(
                context,
                post.isLikedBy(service.currentUserId) 
                    ? Icons.favorite_rounded 
                    : Icons.favorite_border_rounded,
                '${post.likes.length} ${post.likes.length == 1 ? 'Like' : 'Likes'}',
                () async {
                  await service.toggleLike(post.id);
                },
                color: post.isLikedBy(service.currentUserId) 
                    ? Theme.of(context).colorScheme.secondary 
                    : null,
              ),
              _buildPostAction(
                context,
                Icons.chat_bubble_outline_rounded,
                '${post.comments.length} ${post.comments.length == 1 ? 'Comment' : 'Comments'}',
                () {
                  _showCommentsDialog(context, post);
                },
              ),
              _buildPostAction(
                context,
                Icons.chat_bubble_outline_rounded,
                '${post.comments.length} ${post.comments.length == 1 ? 'Comment' : 'Comments'}',
                () {
                  _showCommentsDialog(context, post);
                },
              ),
              _buildPostAction(
                context,
                Icons.share_outlined,
                  '${post.shareCount} ${post.shareCount == 1 ? 'Share' : 'Shares'}',
                  () async {
                    await service.incrementShareCount(post.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Post shared successfully!'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Post shared successfully!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Shows a dialog with comments for a post and allows adding new comments.
  void _showCommentsDialog(BuildContext context, Post post) {
    final TextEditingController commentController = TextEditingController();
    final theme = Theme.of(context);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Comments',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(),
                if (post.comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'No comments yet. Be the first to comment!',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: post.comments.length,
                      separatorBuilder: (context, index) => Divider(
                        color: theme.colorScheme.onSurface.withOpacity(0.1),
                      ),
                      itemBuilder: (context, index) {
                        final comment = post.comments[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                                child: Text(
                                  comment.userName[0].toUpperCase(),
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          comment.userName,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          DateFormat.yMMMd().add_jm().format(
                                                comment.timestamp.toDate(),
                                              ),
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      comment.text,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: commentController,
                        decoration: InputDecoration(
                          hintText: 'Add a comment...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surface.withOpacity(0.8),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.send_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: () async {
                        if (commentController.text.trim().isNotEmpty) {
                          await service.addComment(
                            post.id,
                            commentController.text.trim(),
                          );
                          commentController.clear();
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPostAction(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: color ?? theme.colorScheme.onSurface.withOpacity(0.7),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color ?? theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget to display a single post in a clean card format.
class PostCard extends StatefulWidget {
  final Post post;
  const PostCard({required this.post, super.key});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    // Format timestamp to a readable string
    final formattedDate =
    DateFormat('MMM d, h:mm a').format(widget.post.timestamp.toDate());
    
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          shadowColor: theme.colorScheme.primary.withOpacity(0.2),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Username and Timestamp
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.post.userName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blueGrey[800],
                      ),
                    ),
                    Text(
                      formattedDate,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                // Post Content
                Text(
                  widget.post.text,
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

// --- 7. PROFILE PAGE ---

class ProfilePage extends StatelessWidget {
  final FirebaseService service;
  const ProfilePage({required this.service, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Extract username from email
    final username = service.currentUserEmail.split('@')[0];
    final initials = username.isNotEmpty ? username[0].toUpperCase() : 'U';

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.secondary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.only(top: 48, bottom: 24),
            child: Column(
              children: [
                Hero(
                  tag: 'profile-avatar',
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  username,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  service.currentUserEmail,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account Settings',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSettingsItem(
                      context,
                      icon: Icons.edit,
                      title: 'Edit Profile',
                      onTap: () {
                        _showEditProfileDialog(context);
                      },
                    ),
                    _buildSettingsItem(
                      context,
                      icon: Icons.notifications,
                      title: 'Notifications',
                      onTap: () {
                        _showSettingsDialog(context, 'Notifications', 'Manage your notification preferences');
                      },
                    ),
                    _buildSettingsItem(
                      context,
                      icon: Icons.privacy_tip,
                      title: 'Privacy',
                      onTap: () {
                        _showSettingsDialog(context, 'Privacy Settings', 'Manage your privacy preferences');
                      },
                    ),
                    _buildSettingsItem(
                      context,
                      icon: Icons.help,
                      title: 'Help & Support',
                      onTap: () {
                        _showSettingsDialog(context, 'Help & Support', 'Contact us for assistance');
                      },
                    ),
                    _buildSettingsItem(
                      context,
                      icon: Icons.logout,
                      title: 'Sign Out',
                      isDestructive: true,
                      onTap: () async {
                        await service.signOut();
                        // AuthWrapper will handle navigation after sign out
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
  
  void _showEditProfileDialog(BuildContext context) {
    final theme = Theme.of(context);
    final TextEditingController nameController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Edit Profile',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Display Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        // Save profile changes
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Profile updated successfully!'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  void _showSettingsDialog(BuildContext context, String title, String description) {
    final theme = Theme.of(context);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    bool isDestructive = false,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final color = isDestructive ? theme.colorScheme.error : theme.colorScheme.primary;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: isDestructive 
                    ? theme.colorScheme.error 
                    : theme.colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
