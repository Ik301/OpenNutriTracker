import 'package:flutter/material.dart';

import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/princeton/data/princeton_api.dart';

/// The "Dining hall" tab: browse today's Princeton dining menus by hall and
/// log an item straight into the diary with its published calories/macros.
///
/// Served as the body of the [MainScreen] tab, so it does not provide its
/// own [Scaffold]/[AppBar] (the shared [MainAppbar] in `main_screen.dart`
/// supplies the title).
class PrincetonDiningPage extends StatefulWidget {
  const PrincetonDiningPage({super.key});

  @override
  State<PrincetonDiningPage> createState() => _PrincetonDiningPageState();
}

class _PrincetonDiningPageState extends State<PrincetonDiningPage> {
  String _date() => DateTime.now().toIso8601String().substring(0, 10);

  List<PrincetonLocation>? _locations;
  String? _error;

  PrincetonLocation? _selectedLocation;
  PrincetonMenu? _menu;
  bool _loadingMenu = false;

  bool get _showingMenu => _selectedLocation != null;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    setState(() {
      _error = null;
      _locations = null;
    });
    try {
      final locations = await PrincetonApi.fetchLocations();
      if (!mounted) return;
      setState(() => _locations = locations);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _openLocation(PrincetonLocation location) async {
    setState(() {
      _selectedLocation = location;
      _menu = null;
      _loadingMenu = true;
    });
    try {
      final menu = await PrincetonApi.fetchMenu(location.num, date: _date());
      if (!mounted) return;
      setState(() {
        _menu = menu;
        _loadingMenu = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMenu = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showingMenu) return _buildMenu(context);
    if (_error != null) return _buildError(context);
    if (_locations == null) return const Center(child: CircularProgressIndicator());
    return _buildLocationList(context);
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(_error ?? 'Something went wrong.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _showingMenu ? _retryMenu : _loadLocations,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _retryMenu() {
    if (_selectedLocation != null) {
      _openLocation(_selectedLocation!);
    }
  }

  Widget _buildLocationList(BuildContext context) {
    final locations = _locations!;
    return RefreshIndicator(
      onRefresh: _loadLocations,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Today\'s dining halls',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          for (final location in locations)
            ListTile(
              leading: const Icon(Icons.restaurant_outlined),
              title: Text(location.name),
              subtitle: Text('Location #${location.num}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openLocation(location),
            ),
        ],
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    if (_loadingMenu) return const Center(child: CircularProgressIndicator());
    final menu = _menu;
    if (menu == null) return const Center(child: CircularProgressIndicator());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() {
              _selectedLocation = null;
              _menu = null;
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                children: [
                  const Icon(Icons.arrow_back, size: 20),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${menu.location} · ${menu.date}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _openLocation(_selectedLocation!),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (menu.meals.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No menu published for this day yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                for (final meal in menu.meals) _buildMealSection(context, meal),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMealSection(BuildContext context, PrincetonMeal meal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            meal.meal.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        for (final station in meal.stations) _buildStation(context, meal, station),
      ],
    );
  }

  Widget _buildStation(BuildContext context, PrincetonMeal meal, PrincetonStation station) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Text(
            station.station,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        for (final item in station.items)
          ListTile(
            dense: true,
            title: Text(item.title),
            subtitle: item.calories != null
                ? Text('${item.calories!.round()} kcal')
                : null,
            trailing: const Icon(Icons.add_circle_outline),
            onTap: () => _showLogSheet(context, meal, item),
          ),
      ],
    );
  }

  Future<void> _showLogSheet(
    BuildContext context,
    PrincetonMeal meal,
    PrincetonItem item,
  ) async {
    final result = await showModalBottomSheet<_LogChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _LogItemSheet(meal: meal, item: item),
    );
    if (result == null || !context.mounted) return;
    await _logItem(item, result.type, result.servings);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Logged "${item.title}" at ${result.type.name}.')),
    );
  }

  Future<void> _logItem(PrincetonItem item, IntakeTypeEntity type, double servings) async {
    final day = DateTime.now();
    final calories = item.calories ?? 0;

    // Per-serving nutrition is encoded as "per unit" values. MealNutriments
    // stores per-100g fields (energyPerUnit = x/100), so store the serving
    // values ×100 to land them back on the per-serving basis.
    final meal = MealEntity(
      code: 'princeton:${item.recipeId}:${day.year}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}',
      name: item.title,
      url: null,
      mealQuantity: null,
      mealUnit: 'serving',
      servingQuantity: servings,
      servingUnit: 'serving',
      servingSize: item.servingSize,
      nutriments: MealNutrimentsEntity(
        energyKcal100: calories * 100,
        carbohydrates100: (item.carbs ?? 0) * 100,
        fat100: (item.fat ?? 0) * 100,
        proteins100: (item.protein ?? 0) * 100,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.custom,
    );

    final intake = IntakeEntity(
      id: IdGenerator.getUniqueID(),
      unit: 'serving',
      amount: servings,
      type: type,
      meal: meal,
      dateTime: day,
    );

    await locator<AddIntakeUsecase>().addIntake(intake);

    // Mirror the meal_detail_bloc tracked-day update so the diary calendar
    // and day totals reflect the new entry immediately.
    final addTrackedDay = locator<AddTrackedDayUsecase>();
    if (!await addTrackedDay.hasTrackedDay(day)) {
      final kcalGoal = await locator<GetKcalGoalUsecase>().getKcalGoal();
      final macro = locator<GetMacroGoalUsecase>();
      final carbsGoal = await macro.getCarbsGoal(kcalGoal);
      final fatGoal = await macro.getFatsGoal(kcalGoal);
      final proteinGoal = await macro.getProteinsGoal(kcalGoal);
      await addTrackedDay.addNewTrackedDay(
        day, kcalGoal, carbsGoal, fatGoal, proteinGoal,
      );
    }
    await addTrackedDay.addDayCaloriesTracked(day, intake.totalKcal);
    await addTrackedDay.addDayMacrosTracked(
      day,
      carbsTracked: intake.totalCarbsGram,
      fatTracked: intake.totalFatsGram,
      proteinTracked: intake.totalProteinsGram,
    );
  }
}

/// The choice the log-bottom-sheet returns.
class _LogChoice {
  final IntakeTypeEntity type;
  final double servings;
  const _LogChoice(this.type, this.servings);
}

class _LogItemSheet extends StatefulWidget {
  final PrincetonMeal meal;
  final PrincetonItem item;
  const _LogItemSheet({required this.meal, required this.item});

  @override
  State<_LogItemSheet> createState() => _LogItemSheetState();
}

class _LogItemSheetState extends State<_LogItemSheet> {
  late IntakeTypeEntity _type;
  final TextEditingController _servings = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _type = switch (widget.meal.meal.trim().toLowerCase()) {
      'breakfast' => IntakeTypeEntity.breakfast,
      'lunch' => IntakeTypeEntity.lunch,
      'dinner' => IntakeTypeEntity.dinner,
      _ => IntakeTypeEntity.snack,
    };
  }

  @override
  void dispose() {
    _servings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calories = widget.item.calories?.round();
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.item.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          if (calories != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$calories kcal per serving',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<IntakeTypeEntity>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Meal'),
            items: const [
              DropdownMenuItem(
                value: IntakeTypeEntity.breakfast,
                child: Text('Breakfast'),
              ),
              DropdownMenuItem(
                value: IntakeTypeEntity.lunch,
                child: Text('Lunch'),
              ),
              DropdownMenuItem(
                value: IntakeTypeEntity.dinner,
                child: Text('Dinner'),
              ),
              DropdownMenuItem(
                value: IntakeTypeEntity.snack,
                child: Text('Snack'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _type = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _servings,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Servings',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final servings = double.tryParse(
                _servings.text.replaceAll(',', '.'),
              ) ?? 1;
              Navigator.of(context).pop(_LogChoice(_type, servings));
            },
            child: const Text('Log this item'),
          ),
        ],
      ),
    );
  }
}
