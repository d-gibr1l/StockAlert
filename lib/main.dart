import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

void main() async {
  // Ensure Flutter bindings are initialized before calling database code
  WidgetsFlutterBinding.ensureInitialized();
  
  // Setup sqflite_common_ffi for Windows/Linux desktop support
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  runApp(const StockAlertApp());
}

class StockAlertApp extends StatelessWidget {
  const StockAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StockAlert Pharmacy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F2B3D),
          primary: const Color(0xFF0F2B3D),
          secondary: const Color(0xFF1E7B9E),
        ),
        fontFamily: 'Inter',
      ),
      home: const MainNavigationScreen(),
    );
  }
}

// ------------------- DATA MODELS -------------------

class Medicine {
  String id;
  String name;
  String barcode;
  int quantity;
  DateTime expiry;
  double purchasePrice;
  double sellingPrice;
  String supplier;
  String category;

  Medicine({
    required this.id,
    required this.name,
    this.barcode = '',
    required this.quantity,
    required this.expiry,
    this.purchasePrice = 0.0,
    this.sellingPrice = 0.0,
    this.supplier = '',
    this.category = '',
  });

  // Convert a Medicine into a Map for SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'barcode': barcode,
      'quantity': quantity,
      'expiry': expiry.toIso8601String(),
      'purchasePrice': purchasePrice,
      'sellingPrice': sellingPrice,
      'supplier': supplier,
      'category': category,
    };
  }

  // Convert a Map from SQLite into a Medicine
  factory Medicine.fromMap(Map<String, dynamic> map) {
    return Medicine(
      id: map['id'],
      name: map['name'],
      barcode: map['barcode'],
      quantity: map['quantity'],
      expiry: DateTime.parse(map['expiry']),
      purchasePrice: map['purchasePrice'],
      sellingPrice: map['sellingPrice'],
      supplier: map['supplier'],
      category: map['category'],
    );
  }
}

class SupplierOrder {
  String id;
  String supplier;
  String medicineId;
  String medicineName;
  int quantity;
  String notes;
  String status;
  DateTime date;

  SupplierOrder({
    required this.id,
    required this.supplier,
    required this.medicineId,
    required this.medicineName,
    required this.quantity,
    this.notes = '',
    this.status = 'Ordered',
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplier': supplier,
      'medicineId': medicineId,
      'medicineName': medicineName,
      'quantity': quantity,
      'notes': notes,
      'status': status,
      'date': date.toIso8601String(),
    };
  }

  factory SupplierOrder.fromMap(Map<String, dynamic> map) {
    return SupplierOrder(
      id: map['id'],
      supplier: map['supplier'],
      medicineId: map['medicineId'],
      medicineName: map['medicineName'],
      quantity: map['quantity'],
      notes: map['notes'],
      status: map['status'],
      date: DateTime.parse(map['date']),
    );
  }
}

// ------------------- SQLITE DATABASE HELPER -------------------

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('stockalert.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final dbFilePath = path.join(dbPath, filePath);

    return await openDatabase(
      dbFilePath,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE medicines (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        barcode TEXT,
        quantity INTEGER NOT NULL,
        expiry TEXT NOT NULL,
        purchasePrice REAL,
        sellingPrice REAL,
        supplier TEXT,
        category TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        supplier TEXT NOT NULL,
        medicineId TEXT NOT NULL,
        medicineName TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        notes TEXT,
        status TEXT NOT NULL,
        date TEXT NOT NULL
      )
    ''');
  }

  // --- Medicine Operations ---
  Future<void> insertMedicine(Medicine medicine) async {
    final db = await instance.database;
    await db.insert('medicines', medicine.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateMedicine(Medicine medicine) async {
    final db = await instance.database;
    await db.update('medicines', medicine.toMap(), where: 'id = ?', whereArgs: [medicine.id]);
  }

  Future<List<Medicine>> fetchAllMedicines() async {
    final db = await instance.database;
    final result = await db.query('medicines');
    return result.map((json) => Medicine.fromMap(json)).toList();
  }

  // --- Order Operations ---
  Future<void> insertOrder(SupplierOrder order) async {
    final db = await instance.database;
    await db.insert('orders', order.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateOrder(SupplierOrder order) async {
    final db = await instance.database;
    await db.update('orders', order.toMap(), where: 'id = ?', whereArgs: [order.id]);
  }

  Future<List<SupplierOrder>> fetchAllOrders() async {
    final db = await instance.database;
    final result = await db.query('orders');
    return result.map((json) => SupplierOrder.fromMap(json)).toList();
  }
}

// ------------------- MAIN CONTAINER SCREEN -------------------

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  String _searchQuery = "";
  bool _isLoading = true;

  List<Medicine> _medicines = [];
  List<SupplierOrder> _orders = [];

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  // Fetches data from SQLite and rebuilds the UI
  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    
    final meds = await DatabaseHelper.instance.fetchAllMedicines();
    final ords = await DatabaseHelper.instance.fetchAllOrders();

    // If database is completely empty, you could optionally seed some mock data here, 
    // but starting empty is standard for a fresh DB.

    setState(() {
      _medicines = meds;
      _orders = ords;
      _isLoading = false;
    });
  }

  // Expiry calculation helpers
  int _daysUntilExpiry(DateTime expiryDate) {
    final today = DateTime.now();
    final cleanToday = DateTime(today.year, today.month, today.day);
    final cleanExpiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return cleanExpiry.difference(cleanToday).inDays;
  }

  String _getStockStatus(Medicine med) {
    int days = _daysUntilExpiry(med.expiry);
    if (days < 0) return "expired";
    if (med.quantity <= 10) return "low-stock";
    if (days <= 30) return "near-expiry";
    return "good";
  }

  // Stock alteration engine (now async to update DB)
  Future<void> _adjustStock(String id, int delta) async {
    try {
      final med = _medicines.firstWhere((m) => m.id == id);
      int newQty = med.quantity + delta;
      
      if (newQty < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Stock quantity cannot fall below 0.")),
          );
        }
        return;
      }
      
      med.quantity = newQty;
      await DatabaseHelper.instance.updateMedicine(med);
      await _refreshData();
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error updating stock.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final totalMedicines = _medicines.length;
    final totalValue = _medicines.fold<double>(0.0, (sum, m) => sum + (m.quantity * m.sellingPrice));
    final lowStockCount = _medicines.where((m) => m.quantity <= 10).length;
    final nearExpiryCount = _medicines.where((m) {
      int days = _daysUntilExpiry(m.expiry);
      return days <= 30 && days >= 0;
    }).length;

    final List<Widget> screens = [
      _buildDashboardTab(totalMedicines, totalValue, lowStockCount, nearExpiryCount),
      _buildInventoryTab(),
      _buildOrdersTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'StockAlert Pharmacy',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
            ),
            Text(
              'inventory · expiry · supplier orders',
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85)),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB347),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.notifications_active, size: 16, color: Color(0xFF1E293B)),
                SizedBox(width: 4),
                Text(
                  "Real-time",
                  style: TextStyle(color: Color(0xFF1E293B), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          )
        ],
      ),
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.medication_outlined), selectedIcon: Icon(Icons.medication), label: 'Inventory'),
          NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Orders'),
        ],
      ),
    );
  }

  // ------------------- 1. DASHBOARD TAB -------------------

  Widget _buildDashboardTab(int totalMeds, double totalVal, int lowStock, int nearExpiry) {
    final lowStockList = _medicines.where((m) => m.quantity <= 10).toList();
    final nearExpiryList = _medicines.where((m) {
      int days = _daysUntilExpiry(m.expiry);
      return days <= 30 && days >= 0;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.4,
            children: [
              _buildStatCard("TOTAL MEDS", totalMeds.toString(), Icons.medical_services, Colors.blue),
              _buildStatCard("VALUE", "\$${totalVal.toStringAsFixed(2)}", Icons.attach_money, Colors.green),
              _buildStatCard("LOW STOCK", lowStock.toString(), Icons.warning_amber, Colors.orange),
              _buildStatCard("NEAR EXPIRY", nearExpiry.toString(), Icons.hourglass_empty, Colors.red),
            ],
          ),
          const SizedBox(height: 16),
          _buildAlertSection(
            title: "⚠️ Low Stock Alerts",
            color: const Color(0xFFFFF9E6),
            borderColor: Colors.amber,
            items: lowStockList.isEmpty
                ? [const Text("✅ No low stock alerts")]
                : lowStockList.map((m) => Text("• ${m.name} (Qty: ${m.quantity})", style: const TextStyle(fontWeight: FontWeight.w500))).toList(),
          ),
          const SizedBox(height: 12),
          _buildAlertSection(
            title: "⏰ Near-Expiry (≤30 days)",
            color: const Color(0xFFFFEAEA),
            borderColor: Colors.red,
            items: nearExpiryList.isEmpty
                ? [const Text("✅ No upcoming drug expirations")]
                : nearExpiryList.map((m) => Text("• ${m.name} (Expires: ${m.expiry.year}-${m.expiry.month}-${m.expiry.day} — ${_daysUntilExpiry(m.expiry)} days left)", style: const TextStyle(fontWeight: FontWeight.w500))).toList(),
          ),
          const SizedBox(height: 16),
          _buildExpiryTrendVisual(),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openAddMedicineDialog(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text("Add Med"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _simulateBarcodeScan(),
                  icon: const Icon(Icons.qr_code_scanner, size: 16),
                  label: const Text("Scan"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openNewOrderDialog(),
                  icon: const Icon(Icons.assignment, size: 16),
                  label: const Text("Order"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color accentColor) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2EDF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                Icon(icon, size: 18, color: accentColor),
              ],
            ),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F2B3D))),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertSection({required String title, required Color color, required Color borderColor, required List<Widget> items}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        border: Border(left: BorderSide(color: borderColor, width: 5)),
        borderRadius: const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: borderColor.withRed(150))),
          const SizedBox(height: 6),
          ...items,
        ],
      ),
    );
  }

  Widget _buildExpiryTrendVisual() {
    int c30 = 0, c60 = 0, c90 = 0;

    for (var med in _medicines) {
      int days = _daysUntilExpiry(med.expiry);
      if (days >= 0 && days <= 90) {
        if (days <= 30) {
          c30++;
        } else if (days <= 60) {
          c60++;
        } else if (days <= 90) {
          c90++;
        }
      }
    }

    int maxCount = [c30, c60, c90].reduce((curr, next) => curr > next ? curr : next);
    double graphMax = maxCount == 0 ? 5.0 : maxCount.toDouble();

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2EDF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Expiry Trend (Next 90 Days)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F2B3D))),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildTrendBar("0-30 Days", c30, graphMax),
                  _buildTrendBar("31-60 Days", c60, graphMax),
                  _buildTrendBar("61-90 Days", c90, graphMax),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTrendBar(String label, int value, double graphMax) {
    double pct = value / graphMax;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(value.toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          height: 60 * pct + 2,
          width: 35,
          decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ------------------- 2. INVENTORY TAB -------------------

  Widget _buildInventoryTab() {
    final filteredMedicines = _medicines.where((med) {
      final q = _searchQuery.toLowerCase();
      return med.name.toLowerCase().contains(q) ||
          med.barcode.contains(q) ||
          med.supplier.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: "Search inventory...",
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _openAddMedicineDialog(),
                icon: const Icon(Icons.add_circle, size: 36, color: Color(0xFF1E7B9E)),
              )
            ],
          ),
        ),
        Expanded(
          child: filteredMedicines.isEmpty
              ? const Center(child: Text("No medicines found in database."))
              : ListView.builder(
                  itemCount: filteredMedicines.length,
                  itemBuilder: (context, index) {
                    final med = filteredMedicines[index];
                    final days = _daysUntilExpiry(med.expiry);
                    final status = _getStockStatus(med);

                    Color statusBg, statusText;
                    String statusLabel;

                    switch (status) {
                      case "low-stock":
                        statusBg = const Color(0xFFFEE2E2);
                        statusText = const Color(0xFFB91C1C);
                        statusLabel = "⚠️ Low Stock";
                        break;
                      case "near-expiry":
                        statusBg = const Color(0xFFFFF3CD);
                        statusText = const Color(0xFFB85C00);
                        statusLabel = "⏳ Near Expiry";
                        break;
                      case "expired":
                        statusBg = const Color(0xFFFFEAEA);
                        statusText = const Color(0xFFB91C1C);
                        statusLabel = "❌ Expired";
                        break;
                      default:
                        statusBg = const Color(0xFFE0F2E9);
                        statusText = const Color(0xFF0E6B3E);
                        statusLabel = "✓ Good";
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(med.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(12)),
                                  child: Text(
                                    statusLabel,
                                    style: TextStyle(color: statusText, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                )
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Qty: ${med.quantity}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text("Expiry: ${med.expiry.year}-${med.expiry.month}-${med.expiry.day}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                            Text("Days Left: ${days < 0 ? "Expired" : "$days days"}", style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                            if (med.barcode.isNotEmpty) Text("Barcode: ${med.barcode}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _openAddMedicineDialog(editMed: med),
                                  icon: const Icon(Icons.edit, size: 16),
                                  label: const Text("Edit"),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                                  onPressed: () => _adjustStock(med.id, -1),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                  onPressed: () => _adjustStock(med.id, 10),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ------------------- 3. SUPPLIER ORDERS TAB -------------------

  Widget _buildOrdersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Active Supplier Requests", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ElevatedButton.icon(
                onPressed: () => _openNewOrderDialog(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text("New Order"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.white,
                ),
              )
            ],
          ),
        ),
        Expanded(
          child: _orders.isEmpty
              ? const Center(child: Text("No current supplier orders placed."))
              : ListView.builder(
                  itemCount: _orders.length,
                  itemBuilder: (context, index) {
                    final order = _orders[index];
                    final isReceived = order.status == "Received";

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(order.supplier, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                Chip(
                                  label: Text(order.status, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  backgroundColor: isReceived ? const Color(0xFFE0F2E9) : const Color(0xFFFFF3CD),
                                )
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text("Medicine: ${order.medicineName} | Qty: ${order.quantity}", style: const TextStyle(fontSize: 13)),
                            if (order.notes.isNotEmpty) Text("Notes: ${order.notes}", style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12, color: Colors.grey)),
                            Text("Date Ordered: ${order.date.year}-${order.date.month}-${order.date.day}", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                            if (!isReceived) ...[
                              const Divider(height: 16),
                              Align(
                                alignment: Alignment.centerRight,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    // 1. Update Order Status in DB
                                    order.status = "Received";
                                    await DatabaseHelper.instance.updateOrder(order);

                                    // 2. Increment physical stock in DB
                                    try {
                                      final targetMed = _medicines.firstWhere((m) => m.id == order.medicineId);
                                      targetMed.quantity += order.quantity;
                                      await DatabaseHelper.instance.updateMedicine(targetMed);
                                      
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text("Stock for ${targetMed.name} successfully increased by ${order.quantity} units.")),
                                        );
                                      }
                                    } catch (_) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Warning: Linked medicine could not be found, but status updated.")),
                                        );
                                      }
                                    }
                                    
                                    // 3. Refresh UI
                                    await _refreshData();
                                  },
                                  icon: const Icon(Icons.check, size: 14),
                                  label: const Text("Mark Received"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              )
                            ]
                          ],
                        ),
                      ),
                    );
                  },
                ),
        )
      ],
    );
  }

  // ------------------- DIALOGS / FORMS -------------------

  void _openAddMedicineDialog({Medicine? editMed}) {
    final nameController = TextEditingController(text: editMed?.name ?? "");
    final barcodeController = TextEditingController(text: editMed?.barcode ?? "");
    final qtyController = TextEditingController(text: editMed?.quantity.toString() ?? "0");
    final buyController = TextEditingController(text: editMed?.purchasePrice.toString() ?? "");
    final sellController = TextEditingController(text: editMed?.sellingPrice.toString() ?? "");
    final supplierController = TextEditingController(text: editMed?.supplier ?? "");
    final categoryController = TextEditingController(text: editMed?.category ?? "");
    DateTime selectedDate = editMed?.expiry ?? DateTime.now().add(const Duration(days: 365));

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(editMed == null ? "Add Medicine" : "Edit Medicine"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: nameController, decoration: const InputDecoration(labelText: "Medicine Name *")),
                    TextField(controller: barcodeController, decoration: const InputDecoration(labelText: "Barcode")),
                    TextField(controller: qtyController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Quantity in Stock *")),
                    TextField(controller: buyController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Purchase Price (\$)")),
                    TextField(controller: sellController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Selling Price (\$)")),
                    TextField(controller: supplierController, decoration: const InputDecoration(labelText: "Supplier Name")),
                    TextField(controller: categoryController, decoration: const InputDecoration(labelText: "Category")),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Expiry Date *", style: TextStyle(fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                selectedDate = picked;
                              });
                            }
                          },
                          child: Text("${selectedDate.year}-${selectedDate.month}-${selectedDate.day}"),
                        )
                      ],
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final qty = int.tryParse(qtyController.text) ?? 0;
                    if (name.isEmpty) return;

                    if (editMed == null) {
                      // Insert new record to SQLite
                      final newMed = Medicine(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: name,
                        barcode: barcodeController.text.trim(),
                        quantity: qty,
                        expiry: selectedDate,
                        purchasePrice: double.tryParse(buyController.text) ?? 0.0,
                        sellingPrice: double.tryParse(sellController.text) ?? 0.0,
                        supplier: supplierController.text.trim(),
                        category: categoryController.text.trim(),
                      );
                      await DatabaseHelper.instance.insertMedicine(newMed);
                    } else {
                      // Update existing record in SQLite
                      editMed.name = name;
                      editMed.barcode = barcodeController.text.trim();
                      editMed.quantity = qty;
                      editMed.expiry = selectedDate;
                      editMed.purchasePrice = double.tryParse(buyController.text) ?? 0.0;
                      editMed.sellingPrice = double.tryParse(sellController.text) ?? 0.0;
                      editMed.supplier = supplierController.text.trim();
                      editMed.category = categoryController.text.trim();
                      
                      await DatabaseHelper.instance.updateMedicine(editMed);
                    }
                    
                    if (mounted) Navigator.pop(ctx);
                    await _refreshData(); // Refresh UI with DB state
                  },
                  child: const Text("Save"),
                )
              ],
            );
          },
        );
      },
    );
  }

  void _openNewOrderDialog() {
    if (_medicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add medicines to your inventory before executing supplier orders.")),
      );
      return;
    }

    final supplierController = TextEditingController();
    final qtyController = TextEditingController(text: "50");
    final notesController = TextEditingController();
    Medicine selectedMedicine = _medicines.first;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Create Order"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: supplierController, decoration: const InputDecoration(labelText: "Supplier Name")),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Medicine>(
                      value: selectedMedicine,
                      decoration: const InputDecoration(labelText: "Select Medicine"),
                      items: _medicines.map((m) {
                        return DropdownMenuItem<Medicine>(
                          value: m,
                          child: Text("${m.name} (stock: ${m.quantity})"),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedMedicine = val;
                          });
                        }
                      },
                    ),
                    TextField(controller: qtyController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Quantity to Order")),
                    TextField(controller: notesController, decoration: const InputDecoration(labelText: "Notes (optional)")),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () async {
                    final sup = supplierController.text.trim();
                    final qty = int.tryParse(qtyController.text) ?? 0;
                    if (sup.isEmpty || qty <= 0) return;

                    final newOrder = SupplierOrder(
                      id: "ord_${DateTime.now().millisecondsSinceEpoch}",
                      supplier: sup,
                      medicineId: selectedMedicine.id,
                      medicineName: selectedMedicine.name,
                      quantity: qty,
                      notes: notesController.text.trim(),
                      date: DateTime.now(),
                    );
                    
                    await DatabaseHelper.instance.insertOrder(newOrder);

                    if (mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Order placed to $sup for ${selectedMedicine.name} ($qty units)")),
                      );
                    }
                    await _refreshData();
                  },
                  child: const Text("Place Order"),
                )
              ],
            );
          },
        );
      },
    );
  }

  void _simulateBarcodeScan() {
    final scanController = TextEditingController(text: "890123456789");
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.qr_code_scanner, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text("Simulate Scan"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Enter a barcode mock number below to search or register:"),
              TextField(controller: scanController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Barcode Number")),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                final inputCode = scanController.text.trim();
                Navigator.pop(ctx);
                if (inputCode.isNotEmpty) {
                  final matchIndex = _medicines.indexWhere((m) => m.barcode == inputCode);
                  if (matchIndex != -1) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Match found: ${_medicines[matchIndex].name}. Opening editor.")),
                    );
                    _openAddMedicineDialog(editMed: _medicines[matchIndex]);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("No match found. Registering a new item with this barcode.")),
                    );
                    _openAddMedicineDialog(editMed: Medicine(id: "", name: "", quantity: 0, expiry: DateTime.now().add(const Duration(days: 365)), barcode: inputCode));
                  }
                }
              },
              child: const Text("Submit Scan"),
            )
          ],
        );
      },
    );
  }
}
