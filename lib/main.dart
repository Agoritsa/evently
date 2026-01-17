import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'services/event_service.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:intl/intl.dart'; 
import 'dart:typed_data'; // for web
import 'package:timeago/timeago.dart' as timeago;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService.initialize(); 
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver{
  int _selectedIndex = 0;
  List<dynamic> events = [];
  bool isLoading = false;
  double searchRadius = 50;
  bool hasSearched = false;

  @override
  void initState() {
    super.initState();
    fetchSuggestedEvents();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNotifications();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  // for when the app resumes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNotifications();
    }
  }

    Future<void> _checkNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await NotificationService.checkUpcomingFavoriteEvents();
    } else {
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          NotificationService.checkUpcomingFavoriteEvents();
        }
      });
    }
  }

    Future<void> fetchNearbyEvents() async {
    setState(() {
      isLoading = true;
      hasSearched = true;
    });

    Position? position = await LocationService.getCurrentLocation();

    if (position != null) {
      List<dynamic> fetchedEvents =
          await EventService.fetchEvents(position.latitude, position.longitude, searchRadius);

      setState(() {
        events = fetchedEvents;
      });
    } else {
      print("Could not get user location!");
    }

    setState(() {
      isLoading = false;
    });
  }

  List<dynamic> suggestedEvents = [];
  bool isLoadingSuggested = false;

  Future<void> fetchSuggestedEvents() async {
    setState(() {
      isLoadingSuggested = true;
    });

    try {
      suggestedEvents = await EventService.fetchSuggestedEvents(); 
    } catch (e) {
      print("Failed to load suggested events: $e");
    }

    setState(() {
      isLoadingSuggested = false;
    });
  }

  Widget _getSelectedPage() {
    switch (_selectedIndex) {
      case 0:
        return buildMainContent();
      case 1:
        return EventsPage();
      case 2:
        return CategoriesPage();
      case 3:
        return GuestPage();
      default:
        return buildMainContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF6F5F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(
          "Evently",
          style: GoogleFonts.pacifico(
            color: Colors.deepPurple,
            fontSize: 28,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                final isLoggedIn = snapshot.data != null;

                if (isLoggedIn) {
                  final userEmail = snapshot.data?.email ?? '';

                  return PopupMenuButton<int>(
                    icon: const Icon(Icons.logout, color: Colors.deepPurple),
                    itemBuilder: (context) => [
                      PopupMenuItem<int>(
                        value: 0,
                        child: Text(
                          'Logged in as $userEmail',
                          style: const TextStyle(
                            color: Colors.deepPurple,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const PopupMenuItem<int>(
                        value: 1,
                        child: Text(
                          "Logout",
                          style: TextStyle(color: Colors.deepPurple),
                        ),
                      ),
                    ],
                    onSelected: (item) async {
                      if (item == 1) {
                        await FirebaseAuth.instance.signOut();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Logged out")),
                        );
                      }
                    },
                  );
                } else {
                  return TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LoginScreen(
                            isSignUp: false,
                            onSubmit: (email, password, phone, isSignUp) async {
                              if (isSignUp) {
                                await FirebaseAuth.instance.createUserWithEmailAndPassword(
                                  email: email,
                                  password: password,
                                );
                              } else {
                                await FirebaseAuth.instance.signInWithEmailAndPassword(
                                  email: email,
                                  password: password,
                                );
                              }
                            },
                            onLoginSuccess: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => HomeScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.login, color: Colors.deepPurple),
                    label: const Text(
                      "Login",
                      style: TextStyle(color: Colors.deepPurple),
                    ),
                  );
                }
              },
            ),
          ),
        ],
        iconTheme: const IconThemeData(color: Colors.deepPurple),
      ),
      body: _getSelectedPage(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.event), label: 'Events'),
          BottomNavigationBarItem(icon: Icon(Icons.category), label: 'Categories'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget buildMainContent() {
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.my_location, color: Colors.deepPurple),
                SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<double>(
                    value: searchRadius,
                    isExpanded: true,
                    underline: SizedBox(),
                    items: [10, 20, 50, 100, 200, 500].map((radius) {
                      return DropdownMenuItem<double>(
                        value: radius.toDouble(),
                        child: Text("$radius km"),
                      );
                    }).toList(),
                    onChanged: (double? value) {
                      if (value != null) {
                        setState(() {
                          searchRadius = value;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: fetchNearbyEvents,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              minimumSize: Size(double.infinity, 50),
            ),
            child: isLoading
                ? CircularProgressIndicator(color: Colors.white)
                : Text("Find Events", style: TextStyle(fontSize: 18)),
          ),
          SizedBox(height: 20),
          Expanded(
            child: !hasSearched
                ? buildWelcomeContent()
                : (events.isEmpty
                    ? Center(child: Text("No events found 😢"))
                    : buildEventList()),
          ),
        ],
      ),
    );
  }

Widget buildEventCard(Map<String, dynamic> event) {
  final String eventName = event['name'] ?? 'No Title';
  final String eventDate = event['dates']?['start']?['localDate'] ?? 'No Date';
  final String cityName = event['_embedded']?['venues']?[0]?['city']?['name'] ?? 'Unknown City';

  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          child: event['images'] != null
              ? Image.network(
                  event['images'][0]['url'],
                  height: 100,
                  width: double.infinity,
                  fit: BoxFit.cover,
                )
              : Container(
                  height: 100,
                  color: Colors.deepPurple.shade50,
                  child: Icon(Icons.image_not_supported, size: 40, color: Colors.deepPurple),
                ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eventName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 12, color: Colors.deepPurple),
                  SizedBox(width: 4),
                  Text(
                    eventDate,
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.location_on, size: 12, color: Colors.deepPurple),
                  SizedBox(width: 4),
                  Text(
                    cityName,
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

 Widget buildWelcomeContent() {
  return SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "✨ Suggested Events",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepPurple),
        ),
        SizedBox(height: 10),
        isLoadingSuggested
            ? Center(child: CircularProgressIndicator())
            : suggestedEvents.isEmpty
                ? Center(child: Text("No suggested events found 😢"))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      int crossAxisCount = 1;
                      if (constraints.maxWidth >= 600) {
                        crossAxisCount = 3;
                      } else if (constraints.maxWidth >= 400) {
                        crossAxisCount = 2;
                      }

                      return GridView.count(
                        crossAxisCount: crossAxisCount,
                        shrinkWrap: true,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.2,
                        physics: NeverScrollableScrollPhysics(),
                        children: suggestedEvents.map((event) {
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EventDetailPage(event: event),
                                ),
                              );
                            },
                            child: buildEventCard(event),
                          );
                        }).toList(),
                      );
                    },
                  ),
      ],
    ),
  );
}

Widget buildEventList() {
  return ListView.builder(
    itemCount: events.length,
    itemBuilder: (context, index) {
      var event = events[index];
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EventDetailPage(event: event),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: buildEventCard(event),
        ),
      );
    },
  );
}
}

class EventDetailPage extends StatefulWidget {
  final Map<String, dynamic> event;

  EventDetailPage({required this.event});

  @override
  _EventDetailPageState createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  double _rating = 0;
  TextEditingController _commentController = TextEditingController();
  List<Map<String, dynamic>> _reviews = [];
  bool _isSubmitting = false;
  bool _isFavorited = false;
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    fetchReviews();
    checkIfFavorited();
  }

  Future<void> checkIfFavorited() async {
    if (_currentUser == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('favorites')
        .doc(widget.event['id'])
        .get();

    setState(() {
      _isFavorited = doc.exists;
    });
  }

  Future<void> toggleFavorite(Map<String, dynamic> flattenedEvent) async { 
  if (_currentUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Please log in to favorite events.')),
    );
    return;
  }

  final userId = _currentUser!.uid;
  final eventId = flattenedEvent['id'];

  final favRef = FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('favorites')
      .doc(eventId);

  final notifiedRef = FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('notifiedEvents')
      .doc(eventId);

  if (_isFavorited) {
    await favRef.delete();
    await notifiedRef.delete();  
  } else {
    await favRef.set(flattenedEvent);
  }

  setState(() {
    _isFavorited = !_isFavorited;
  });
}

  Future<void> fetchReviews() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('reviews')
        .doc(widget.event['id'])
        .collection('userReviews')
        .orderBy('timestamp', descending: true)
        .get();

    setState(() {
      _reviews = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        data['timestamp'] = data['timestamp'];
        return data;
      }).toList();
    });
  }

  Future<void> submitReview() async {
    if (_rating == 0 || _commentController.text.trim().isEmpty) return;

    setState(() {
      _isSubmitting = true;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You must be logged in to leave a review.')),
      );
      setState(() {
        _isSubmitting = false;
      });
      return;
    }

    try {
      final userProfile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final firstName = userProfile.data()?['firstName'] ?? '';
      final lastName = userProfile.data()?['lastName'] ?? '';

      final reviewData = {
        'userId': user.uid,
        'firstName': firstName,
        'lastName': lastName,
        'rating': _rating,
        'comment': _commentController.text.trim(),
        'timestamp': Timestamp.now(),
      };

      await FirebaseFirestore.instance
          .collection('reviews')
          .doc(widget.event['id'])
          .collection('userReviews')
          .add(reviewData);

      _commentController.clear();
      _rating = 0;
      await fetchReviews();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting review: $e')),
      );
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  Future<void> deleteReview(String reviewId) async {
    try {
      await FirebaseFirestore.instance
          .collection('reviews')
          .doc(widget.event['id'])
          .collection('userReviews')
          .doc(reviewId)
          .delete();

      await fetchReviews();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Review deleted successfully.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting review: $e')),
      );
    }
  }

  void confirmDeleteReview(String reviewId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Review"),
        content: Text("Are you sure you want to delete your review?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              deleteReview(reviewId);
            },
            child: Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget buildStarRating() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return IconButton(
          icon: Icon(
            index < _rating ? Icons.star : Icons.star_border,
            color: Colors.amber,
          ),
          onPressed: () {
            setState(() {
              _rating = (index + 1).toDouble();
            });
          },
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {

  final event = widget.event;
  final String title = event['name'] ?? 'No Title';
  final String? imageUrl = (event['image'] != null && event['image'].toString().isNotEmpty)? event['image']: (event['images'] != null && event['images'].isNotEmpty? event['images'][0]['url']: null);
  final String date = event['date'] ?? event['dates']?['start']?['localDate'] ?? 'No Date';
  final String time = event['time'] ?? event['dates']?['start']?['localTime'] ?? '';
  final String description = event['description'] ?? event['info'] ?? 'No Description Available.';
  final String? venue = event['location'] ?? event['_embedded']?['venues']?[0]?['name'];
  final String? city = event['city'] ?? event['_embedded']?['venues']?[0]?['city']?['name'];
  final String? country = event['country'] ?? event['_embedded']?['venues']?[0]?['country']?['name'];

  // flattening data for favoriting 
  Map<String, dynamic> _flattenEvent(Map<String, dynamic> event) {
    return {
      'id': event['id'],
      'name': title,
      'image': imageUrl ?? '',
      'date': date,
      'time': time,
      'description': description,
      'location': venue ?? '',
      'city': city ?? '',
      'country': country ?? '',
    };
  }

    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: Icon(
              _isFavorited ? Icons.favorite : Icons.favorite_border,
              color: _isFavorited ? Colors.red : Colors.grey,
              size: 28,
            ),
            onPressed: () => toggleFavorite(_flattenEvent(event)),
          ),
        ],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                // Event image
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  clipBehavior: Clip.antiAlias,
                  elevation: 4,
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          width: double.infinity,
                          height: 220,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          height: 220,
                          color: Colors.deepPurple.shade50,
                          child: Icon(Icons.image_not_supported, size: 80, color: Colors.deepPurple),
                        ),
                ),

                SizedBox(height: 16),

                // Event details
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 20, color: Colors.deepPurple),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                date + (time.isNotEmpty ? ' at $time' : ''),
                                style: TextStyle(fontSize: 16),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        if (venue != null || city != null)
                          Row(
                            children: [
                              Icon(Icons.location_on, size: 20, color: Colors.deepPurple),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${venue ?? ''}${venue != null && city != null ? ', ' : ''}${city ?? ''}${country != null ? ', $country' : ''}',
                                  style: TextStyle(fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // Description Card
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 3,
                  child: Container(
                    width: double.infinity,
                    constraints: BoxConstraints(minHeight: 160),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("About the Event", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                        SizedBox(height: 8),
                        Text(
                          description.isNotEmpty ? description : "No description available.",
                          style: TextStyle(fontSize: 16, height: 1.5, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // Review form
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Center(child: Text("Leave a Review", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple))),
                        SizedBox(height: 8),
                        Center(child: buildStarRating()),
                        TextField(
                          controller: _commentController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: "Write your comment...",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        SizedBox(height: 8),
                        Center(
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : submitReview,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                            child: _isSubmitting
                                ? CircularProgressIndicator(color: Colors.white)
                                : Text("Submit Review"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // Display reviews
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Reviews", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                        SizedBox(height: 8),
                        _reviews.isEmpty
                            ? Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  "No reviews yet. Be the first to review!",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: NeverScrollableScrollPhysics(),
                                itemCount: _reviews.length,
                                itemBuilder: (context, index) {
                                  final review = _reviews[index];
                                  final timestamp = review['timestamp'] as Timestamp?;
                                  final timeAgo = timestamp != null
                                      ? timeago.format(timestamp.toDate())
                                      : '';
                                  final reviewerName =
                                      "${review['firstName'] ?? ''} ${review['lastName'] ?? ''}".trim();
                                  final currentUser = FirebaseAuth.instance.currentUser;
                                  final isReviewOwner = currentUser != null && currentUser.uid == review['userId'];

                                  return Card(
                                    margin: EdgeInsets.symmetric(vertical: 8),
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: List.generate(5, (i) {
                                                  return Icon(
                                                    i < (review['rating'] ?? 0) ? Icons.star : Icons.star_border,
                                                    color: Colors.amber,
                                                    size: 20,
                                                  );
                                                }),
                                              ),
                                              if (isReviewOwner)
                                                PopupMenuButton<String>(
                                                  onSelected: (value) {
                                                    if (value == 'delete') {
                                                      confirmDeleteReview(review['id']);
                                                    }
                                                  },
                                                  itemBuilder: (context) => [
                                                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                                                  ],
                                                ),
                                            ],
                                          ),
                                          SizedBox(height: 4),
                                          Text(review['comment'] ?? '', style: TextStyle(fontSize: 16)),
                                          SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                reviewerName.isNotEmpty ? "- $reviewerName" : "- Anonymous",
                                                style: TextStyle(fontSize: 12, color: Colors.grey),
                                              ),
                                              Text(timeAgo, style: TextStyle(fontSize: 12, color: Colors.grey)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
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
    );
  }
}

class EventsPage extends StatefulWidget {
  @override
  _EventsPageState createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  List<dynamic> allEvents = [];
  List<dynamic> filteredEvents = [];
  bool isLoading = true;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    fetchAllEvents();
  }

  Future<void> fetchAllEvents() async {
    // Example coordinates - could be anything since we want all events
    double latitude = 0.0;
    double longitude = 0.0;
    double radius = 5000;

    List<dynamic> events = await EventService.fetchEvents(latitude, longitude, radius);

    setState(() {
      allEvents = events;
      filteredEvents = events;
      isLoading = false;
    });
  }

  void filterEvents(String query) {
    setState(() {
      searchQuery = query.toLowerCase();
      filteredEvents = allEvents.where((event) {
        final name = (event['name'] ?? '').toString().toLowerCase();
        return name.contains(searchQuery);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return isLoading
        ? Center(child: CircularProgressIndicator(color: Colors.deepPurple))
        : Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  onChanged: filterEvents,
                  decoration: InputDecoration(
                    hintText: 'Search events...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),

              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => CommunityEventsPage()),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 56, 
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.person_add, color: Colors.deepPurple),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "View events added by users",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios, color: Colors.deepPurple, size: 16),
                      ],
                    ),
                  ),
                ),
              ),

              Expanded(
                child: filteredEvents.isEmpty
                    ? Center(child: Text("No events found."))
                    : ListView.builder(
                        itemCount: filteredEvents.length,
                        itemBuilder: (context, index) {
                          var event = filteredEvents[index];
                          return Card(
                            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              leading: event['images'] != null
                                  ? Image.network(
                                      event['images'][0]['url'],
                                      width: 60,
                                      fit: BoxFit.cover,
                                    )
                                  : Icon(Icons.event, size: 50, color: Colors.deepPurple),
                              title: Text(event['name'] ?? "No Title"),
                              subtitle: Text(event['dates']?['start']?['localDate'] ?? "No Date"),
                              trailing: Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EventDetailPage(event: event),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
  }
}

class CommunityEventsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Community Events"),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddCommunityEventPage()),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                ),
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.add, color: Colors.deepPurple),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Add Your Event",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('community_events')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: Colors.deepPurple));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Text("No user-added events yet."));
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data()! as Map<String, dynamic>;

                    final title = (data['title'] ?? 'Untitled Event').toString();
                    final timestamp = data['date'];
                    String dateStr = 'No Date';
                    if (timestamp is Timestamp) {
                      final dt = timestamp.toDate();
                      dateStr =
                          "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
                    } else if (timestamp is String) {
                      dateStr = timestamp;
                    }

                    final imageUrl = data['imageUrl'] as String?;
                    final location = data['location'] as String? ?? '';

                    return Card(
                      margin: EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: imageUrl != null && imageUrl.isNotEmpty
                            ? Image.network(imageUrl, width: 60, fit: BoxFit.cover)
                            : Icon(Icons.event, size: 48, color: Colors.deepPurple),
                        title: Text(title),
                        subtitle: Text(dateStr + (location.isNotEmpty ? " • $location" : "")),
                        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.deepPurple),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CommunityEventDetailPage(
                                eventDocId: doc.id,
                                eventData: data,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CommunityEventDetailPage extends StatefulWidget {
  final String eventDocId;
  final Map<String, dynamic> eventData;

  const CommunityEventDetailPage({
    required this.eventDocId,
    required this.eventData,
  });

  @override
  _CommunityEventDetailPageState createState() => _CommunityEventDetailPageState();
}

class _CommunityEventDetailPageState extends State<CommunityEventDetailPage> {
  String? creatorName;

  @override
  void initState() {
    super.initState();
    _loadCreatorName();
  }

Future<void> _loadCreatorName() async {
  final uid = widget.eventData['createdBy'];
  if (uid != null) {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        setState(() {
          creatorName = "${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}".trim();
          if (creatorName == null || creatorName!.isEmpty) {
            creatorName = 'Unknown';
          }
        });
      } else {
        setState(() {
          creatorName = 'Unknown';
        });
      }
    } catch (e) {
      setState(() {
        creatorName = 'Unknown';
      });
      print("Error loading creator name: $e");
    }
  }
}

  @override
  Widget build(BuildContext context) {
    final title = widget.eventData['title'] ?? 'Untitled Event';
    final description = widget.eventData['description'] ?? '';
    final location = widget.eventData['location'] ?? '';
    final timestamp = widget.eventData['date'];

    String dateStr = 'No Date';
    if (timestamp is Timestamp) {
      final dt = timestamp.toDate();
      dateStr =
          "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    } else if (timestamp is String) {
      dateStr = timestamp;
    }

    final imageUrl = widget.eventData['imageUrl'] as String?;
    final defaultImage = 'assets/images/event_default_image.png'; // asset path

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                (imageUrl != null && imageUrl.isNotEmpty)
                    ? Image.network(
                        imageUrl,
                        width: double.infinity,
                        height: 250,
                        fit: BoxFit.cover,
                      )
                    : Image.asset(
                        defaultImage,
                        width: double.infinity,
                        height: 250,
                        fit: BoxFit.cover,
                      ),
                Container(
                  height: 250,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black54, Colors.transparent],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),
              ],
            ),

            // Card for event details
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 18, color: Colors.deepPurple),
                          SizedBox(width: 6),
                          Text(dateStr,
                              style: TextStyle(
                                  fontSize: 16, color: Colors.grey[700])),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.person,
                              size: 18, color: Colors.deepPurple),
                          SizedBox(width: 6),
                          Text(
                            "Created by: ${creatorName ?? 'Loading...'}",
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      if (location.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.location_on,
                                size: 18, color: Colors.deepPurple),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(location,
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[700])),
                            ),
                          ],
                        ),
                      Divider(height: 24, thickness: 1),
                      Text(
                        "About this event",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 8),
                      Text(
                        description.isNotEmpty
                            ? description
                            : "No description provided.",
                        style: TextStyle(fontSize: 16, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// for adding events created by the users
class AddCommunityEventPage extends StatefulWidget {
  @override
  _AddCommunityEventPageState createState() => _AddCommunityEventPageState();
}

class _AddCommunityEventPageState extends State<AddCommunityEventPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  final _imageUrlController = TextEditingController();
  DateTime? _selectedDate;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("You must be logged in to add an event.")),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('community_events').add({
      'title': _titleController.text.trim(),
      'description': _descController.text.trim(),
      'location': _locationController.text.trim(),
      'imageUrl': _imageUrlController.text.trim(),
      'date': _selectedDate != null ? Timestamp.fromDate(_selectedDate!) : null,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': user.uid,
    });

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Add Your Event"), backgroundColor: Colors.deepPurple),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(labelText: "Event Title"),
                validator: (value) => value!.isEmpty ? "Enter a title" : null,
              ),
              TextFormField(
                controller: _descController,
                decoration: InputDecoration(labelText: "Description"),
                maxLines: 3,
              ),
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(labelText: "Location"),
              ),
              TextFormField(
                controller: _imageUrlController,
                decoration: InputDecoration(labelText: "Image URL (optional)"),
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedDate == null
                          ? "No date chosen"
                          : "Date: ${_selectedDate!.year}-${_selectedDate!.month}-${_selectedDate!.day}",
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _pickDate,
                    child: Text("Pick Date"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white),
                  ),
                ],
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _submit,
                child: Text("Submit"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CategoriesPage extends StatelessWidget {
  final List<Map<String, dynamic>> categories = [
    {'name': 'Music', 'icon': Icons.music_note, 'color': Colors.pink},
    {'name': 'Sports', 'icon': Icons.sports_soccer, 'color': Colors.blue},
    {'name': 'Art', 'icon': Icons.brush, 'color': Colors.deepOrange},
    {'name': 'Technology', 'icon': Icons.computer, 'color': Colors.teal},
    {'name': 'Theater', 'icon': Icons.theater_comedy, 'color': Colors.indigo},
    {'name': 'Food', 'icon': Icons.fastfood, 'color': Colors.green},
    {'name': 'Education', 'icon': Icons.school, 'color': Colors.cyan},
    {'name': 'Networking', 'icon': Icons.group, 'color': Colors.purple},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.category, color: Colors.deepPurple),
              SizedBox(width: 8),
              Text(
                'Explore Categories',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = 2;
              if (constraints.maxWidth > 600) {
                crossAxisCount = 3; // More columns on larger screens
              }

              return GridView.count(
                padding: EdgeInsets.symmetric(horizontal: 12),
                crossAxisCount: crossAxisCount,
                childAspectRatio: 1.2, // Higher = shorter cards
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: categories.map((category) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CategoryEventsPage(categoryName: category['name']),
                        ),
                      );
                    },
                    child: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: category['color'].withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: category['color'], width: 1),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(category['icon'], color: category['color'], size: 28), // smaller
                          SizedBox(height: 6),
                          Text(
                            category['name'],
                            style: TextStyle(
                              color: category['color'],
                              fontWeight: FontWeight.bold,
                              fontSize: 13, // smaller text
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.all(16),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb, color: Colors.deepPurple),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tip: Tap on a category to find related events near you!',
                    style: TextStyle(color: Colors.deepPurple),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 12),
      ],
    );
  }
}

class CategoryEventsPage extends StatefulWidget {
  final String categoryName;

  CategoryEventsPage({required this.categoryName});

  @override
  _CategoryEventsPageState createState() => _CategoryEventsPageState();
}

class _CategoryEventsPageState extends State<CategoryEventsPage> {
  List<dynamic> _events = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    fetchCategoryEvents();
  }

  Future<void> fetchCategoryEvents() async {
    try {
      final events = await EventService.fetchEventsByCategory(widget.categoryName);
      setState(() {
        _events = events;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
        backgroundColor: Colors.deepPurple,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple, width: 1),
              ),
              child: Text(
                '${widget.categoryName} Events',
                style: GoogleFonts.pacifico(
                  fontSize: 22,
                  color: Colors.deepPurple,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            /// Event Content
            _isLoading
                ? Center(child: CircularProgressIndicator())
                : _hasError
                    ? Center(child: Text('Failed to load events.'))
                    : _events.isEmpty
                        ? Center(child: Text('No events found for this category.'))
                        : Expanded(
                            child: ListView.builder(
                              itemCount: _events.length,
                              itemBuilder: (context, index) {
                                final event = _events[index];
                                final imageUrl = event['images'] != null && event['images'].isNotEmpty
                                    ? event['images'][0]['url']
                                    : null;
                                final title = event['name'] ?? 'No Title';
                                final date = event['dates']?['start']?['localDate'] ?? 'No Date';
                                final venue = event['_embedded']?['venues']?[0]?['name'] ?? 'Unknown Venue';

                                return GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EventDetailPage(event: event),
                                      ),
                                    );
                                  },
                                  child: Card(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    margin: EdgeInsets.symmetric(vertical: 8),
                                    elevation: 3,
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.only(
                                              topLeft: Radius.circular(16),
                                              bottomLeft: Radius.circular(16)),
                                          child: imageUrl != null
                                              ? Image.network(
                                                  imageUrl,
                                                  width: 100,
                                                  height: 100,
                                                  fit: BoxFit.cover,
                                                )
                                              : Container(
                                                  width: 100,
                                                  height: 100,
                                                  color: Colors.deepPurple.shade50,
                                                  child: Icon(Icons.image_not_supported,
                                                      color: Colors.deepPurple),
                                                ),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  date,
                                                  style: TextStyle(color: Colors.grey[600]),
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  venue,
                                                  style: TextStyle(color: Colors.grey[600]),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ],
        ),
      ),
    );
  }
}

class GuestPage extends StatelessWidget {
  const GuestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;

        if (user != null) {
          return ProfilePage();
        } else {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 80, color: Colors.grey),
                  const SizedBox(height: 20),
                  const Text('You need to be logged in to view your profile.'),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text("Log In / Sign Up"),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LoginScreen(
                            isSignUp: false,
                            onSubmit: (email, password, phone, isSignUp) async {
                              try {
                                UserCredential userCredential;

                                if (isSignUp) {
                                  userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                                    email: email,
                                    password: password,
                                  );

                                  // Create Firestore user profile
                                  await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
                                    'firstName': '',
                                    'lastName': '',
                                    'phone': phone,
                                    'bio': '',
                                    'notificationsEnabled': true,
                                  });
                                } else {
                                  userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
                                    email: email,
                                    password: password,
                                  );
                                }

                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Login error: ${e.toString()}"),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                            onLoginSuccess: () {
                              Navigator.pop(context); 
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }
}

class ProfilePage extends StatefulWidget {
  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final picker = ImagePicker();
  File? _profileImage;
  String? _profileImageUrl;

  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController bioController = TextEditingController();

  bool notificationsEnabled = true;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        errorMessage = "User not logged in.";
        isLoading = false;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(Duration(seconds: 7));

      final data = doc.data();

      setState(() {
        if (data != null) {
          firstNameController.text = data['firstName'] ?? '';
          lastNameController.text = data['lastName'] ?? '';
          phoneController.text = data['phone'] ?? '';
          bioController.text = data['bio'] ?? '';
          notificationsEnabled = data['notificationsEnabled'] ?? true;
          _profileImageUrl = data['profile_image_url'];
        }
        emailController.text = user.email ?? '';
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = "Failed to load profile: $e";
        isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'firstName': firstNameController.text,
      'lastName': lastNameController.text,
      'phone': phoneController.text,
      'bio': bioController.text,
      'notificationsEnabled': notificationsEnabled,
    }, SetOptions(merge: true));

    if (notificationsEnabled) {
      final granted = await NotificationService.requestPermission();
      if (granted) {
        NotificationService.showLocalNotification(
          "Profile Saved",
          "Your changes have been saved successfully.",
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Notification permission denied.")),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Profile updated!")),
      );
    }
  }

  Future<String?> uploadImageToCloudinaryWeb(Uint8List fileBytes, String fileName) async {
    final uploadPreset = 'flutter_unsigned';
    final url = Uri.parse('https://api.cloudinary.com/v1_1/djv0474f9/image/upload');

    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));

    try {
      final response = await request.send();
      final resStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(resStr);
        return jsonResponse['secure_url'];
      } else {
        print("Cloudinary upload failed: ${response.statusCode}");
        print(resStr);
        return null;
      }
    } catch (e) {
      print("Upload error: $e");
      return null;
    }
  }

  Future<String?> uploadImageToCloudinary(File imageFile, String userId) async {
    final uploadPreset = 'flutter_unsigned';
    final url = Uri.parse('https://api.cloudinary.com/v1_1/djv0474f9/image/upload');

    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = uploadPreset
      ..fields['public_id'] = 'user_profiles/$userId'
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

    try {
      final response = await request.send();
      final resStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(resStr);
        return jsonResponse['secure_url'];
      } else {
        print("Cloudinary upload failed: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("Upload error: $e");
      return null;
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String? imageUrl;

    if (kIsWeb) {
      final bytes = await pickedFile.readAsBytes();
      imageUrl = await uploadImageToCloudinaryWeb(bytes, pickedFile.name);
    } else {
      final file = File(pickedFile.path);
      imageUrl = await uploadImageToCloudinary(file, user.uid);
    }

    if (imageUrl != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'profile_image_url': imageUrl}, SetOptions(merge: true));

      setState(() {
        _profileImage = kIsWeb ? null : File(pickedFile.path);
        _profileImageUrl = imageUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Profile image updated!")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Image upload failed.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (errorMessage != null) {
      return Scaffold(
        body: Center(child: Text(errorMessage!, style: TextStyle(color: Colors.red))),
      );
    }

    return _buildProfileForm();
  }

  Widget _buildProfileForm() {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple.shade50, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 60,
                  backgroundImage: _profileImage != null
                      ? FileImage(_profileImage!)
                      : (_profileImageUrl != null
                          ? NetworkImage(_profileImageUrl!)
                          : const NetworkImage('https://i.pravatar.cc/150?img=47')),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.camera_alt, size: 18, color: Colors.deepPurple),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text(
                "Edit Profile",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepPurple),
              ),
              SizedBox(height: 20),
              buildEditableField("First Name", firstNameController),
              buildEditableField("Last Name", lastNameController),
              buildEditableField("Email", emailController, enabled: false),
              buildEditableField("Phone", phoneController),
              buildEditableField("Bio", bioController, maxLines: 3),
              SizedBox(height: 20),
              Text(
                "Your Events",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.deepPurple),
              ),
              SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => FavoriteEventsPage()),
                  );
                },
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                  child: ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    title: Text("View Favorite Events"),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.deepPurple),
                  ),
                ),
              ),
              SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  final userId = FirebaseAuth.instance.currentUser?.uid;
                  if (userId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserCreatedEventsPage(userId: userId),
                      ),
                    );
                  }
                },
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                  child: ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    title: Text("View Events Created by You"),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.deepPurple),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Text(
                "Settings",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.deepPurple),
              ),
              SizedBox(height: 10),
              buildSettingsCard(),
              SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _saveProfile,
                icon: Icon(Icons.save),
                label: Text("Save Changes"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildEditableField(String label, TextEditingController controller,
      {int maxLines = 1, bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.deepPurple),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.deepPurple, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget buildSettingsCard() {
    return Card(
      color: Colors.deepPurple.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              value: notificationsEnabled,
              onChanged: (val) => setState(() => notificationsEnabled = val),
              title: Text("Enable Notifications"),
              activeColor: Colors.deepPurple,
            ),
          ],
        ),
      ),
    );
  }
}

class UserCreatedEventsPage extends StatelessWidget {
  final String userId;

  const UserCreatedEventsPage({required this.userId});

  void _deleteEvent(BuildContext context, String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete Event"),
        content: Text("Are you sure you want to delete this event?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              "Delete",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('community_events')
          .doc(docId)
          .delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Event deleted")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Created by you"),
        backgroundColor: Colors.deepPurple,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('community_events')
            .where('createdBy', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text("You haven’t created any events yet."));
          }

          final events = snapshot.data!.docs;

          return ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index].data() as Map<String, dynamic>;

              String dateStr = '';
              if (event['createdAt'] is Timestamp) {
                dateStr = DateFormat('yyyy-MM-dd – HH:mm')
                    .format((event['createdAt'] as Timestamp).toDate());
              } else if (event['createdAt'] is String) {
                dateStr = event['createdAt'];
              }

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  title: Text(
                    event['title'] ?? 'No title',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text("Created on $dateStr"),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') {
                        _deleteEvent(context, events[index].id);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text("Delete"),
                          ],
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CommunityEventDetailPage(
                          eventData: event,
                          eventDocId: events[index].id,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class FavoriteEventsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text("Favorite Events"),
        backgroundColor: Colors.deepPurple,
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .collection('favorites')
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text("You haven't favorited any events yet."));
          }

          final favoriteDocs = snapshot.data!.docs;

          return ListView.builder(
            padding: EdgeInsets.all(12),
            itemCount: favoriteDocs.length,
            itemBuilder: (context, index) {
              final doc = favoriteDocs[index];
              final event = doc.data() as Map<String, dynamic>;

              final eventName = event['name']?.toString().trim().isNotEmpty == true
                  ? event['name']
                  : 'Unnamed Event';

              final eventDate = event['date'] ?? 'No Date';
              final eventImage = event['image']?.toString().isNotEmpty == true ? event['image'] : null;

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: eventImage != null
                      ? Image.network(
                          eventImage,
                          width: 60,
                          fit: BoxFit.cover,
                        )
                      : Icon(Icons.event, size: 50, color: Colors.deepPurple),
                  title: Text(eventName),
                  subtitle: Text(eventDate),
                  trailing: Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EventDetailPage(event: event),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final bool isSignUp;
  final Future<void> Function(String email, String password, String phone, bool isSignUp) onSubmit;
  final VoidCallback onLoginSuccess;

  const LoginScreen({
    required this.isSignUp,
    required this.onSubmit,
    required this.onLoginSuccess,
    Key? key,
  }) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

 void _submit() async {
  if (_formKey.currentState!.validate()) {
    try {
      await widget.onSubmit(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        _phoneController.text.trim(),
        widget.isSignUp,
      );

      if (!mounted) return;

      if (widget.isSignUp) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("You're signed up! Enjoy the app"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Login successful!"), 
          ),
        );

        widget.onLoginSuccess();
      }

      } catch (e) {
        if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Login failed: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isSignUp ? 'Sign Up' : 'Login'),
        leading: BackButton(color: Colors.black),
        backgroundColor: Colors.deepPurple,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.isSignUp ? 'Create Account' : 'Login',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    SizedBox(height: 20),
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) =>
                          value!.isEmpty ? 'Please enter your email' : null,
                    ),
                    SizedBox(height: 12),
                    if (widget.isSignUp)
                      TextFormField(
                        controller: _phoneController,
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (value) =>
                            value!.isEmpty ? 'Enter your phone number' : null,
                      ),
                    if (widget.isSignUp) SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      obscureText: true,
                      validator: (value) =>
                          value!.length < 6 ? 'Password must be at least 6 characters' : null,
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _submit,
                      child: Text(widget.isSignUp ? 'Sign Up' : 'Login'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        padding: EdgeInsets.symmetric(horizontal: 50, vertical: 14),
                        textStyle: TextStyle(fontSize: 16),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(widget.isSignUp
                            ? "Already have an account?"
                            : "Don't have an account?"),
                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LoginScreen(
                                  isSignUp: !widget.isSignUp,
                                  onSubmit: widget.onSubmit,
                                  onLoginSuccess: widget.onLoginSuccess,
                                ),
                              ),
                            );
                          },
                          child: Text(
                            widget.isSignUp ? "Login" : "Sign Up",
                            style: TextStyle(color: Colors.deepPurple),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}