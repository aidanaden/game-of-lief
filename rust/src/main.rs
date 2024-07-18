use std::{collections::HashMap, time::Duration};

use clap::Parser;
use rand::Rng;

use clap_num::number_range;

fn less_than_4(s: &str) -> Result<usize, String> {
    number_range(s, 0, 4)
}

/// Game of life simulation program
#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
struct Cli {
    #[arg(short, long, default_value_t = 60)]
    size: i32,
    #[arg(long, default_value_t = 35)]
    init_lives: u32,
    #[arg(long, default_value_t = 2, value_parser=less_than_4)]
    init_neighbors: usize,
    #[arg(short, long, default_value_t = 150)]
    generations_till_reset: u32,
    #[arg(short, long, default_value_t = 10)]
    max_dead_generations: u32,
    #[arg(short, long, default_value_t = 125)]
    refresh_rate: u64,
}

fn main() {
    let cli = Cli::parse();
    let mut runs = 1;
    let mut generation = 0;
    let mut prev_population = 0;
    let mut dead_generations = 0;
    let max_size = cli.size * cli.size;
    let mut grid = Grid::new(cli.size);
    grid.seed(cli.init_lives, cli.init_neighbors);
    grid.print();

    loop {
        generation += 1;

        // bring cursor to "home" location, in just about any currently-used
        // terminal emulation mode
        print!("\x1B[2J\x1B[H");
        grid.next();
        grid.print();

        let population = grid.num_live();

        println!("Runs: {runs}");
        println!("Generation: {generation}");
        println!("Total population: {population}/{max_size}");

        // Increment dead generations, reset if past threshold
        if population == 0 || prev_population == population {
            if dead_generations > cli.max_dead_generations {
                runs += 1;
                generation = 0;
                dead_generations = 0;
                grid.seed(cli.init_lives, cli.init_neighbors);
            }
            dead_generations += 1;
        }

        if generation == cli.generations_till_reset {
            runs += 1;
            generation = 0;
            dead_generations = 0;
            grid.seed(cli.init_lives, cli.init_neighbors);
        }

        prev_population = population;

        let millis = Duration::from_millis(cli.refresh_rate);
        std::thread::sleep(millis);
    }
}

const ALL_NEIGHBORS: [(i32, i32); 8] = [
    (0, 1),
    (1, 1),
    (1, 0),
    (1, -1),
    (0, -1),
    (-1, -1),
    (-1, 0),
    (-1, 1),
];

#[derive(PartialEq, Eq, Hash, Clone)]
struct Point {
    x: i32,
    y: i32,
}

impl Point {
    pub fn new(x: i32, y: i32) -> Self {
        Self { x, y }
    }

    pub fn get_neighbors(&self, max_neighbors: usize) -> Vec<Point> {
        let num_neighbors = {
            if max_neighbors > 8 {
                8
            } else {
                max_neighbors
            }
        };
        let neighbors = (0..num_neighbors)
            .into_iter()
            .filter_map(|n_i| {
                if let Some((neig_x, neig_y)) = ALL_NEIGHBORS.get(n_i) {
                    Some(Point::new(self.x + neig_x, self.y + neig_y))
                } else {
                    None
                }
            })
            .collect();
        neighbors
    }
}

struct Grid {
    live_points: HashMap<Point, bool>,
    size: i32,
}

impl Grid {
    pub fn new(size: i32) -> Self {
        Self {
            live_points: HashMap::new(),
            size,
        }
    }

    pub fn seed(&mut self, num_live: u32, init_neighbors: usize) {
        // Seed values will be generated between points (self.size / 4, self.size / 4)
        // to (self.size - (self.size / 4), self.size - (self.size / 4))
        let window = rand::thread_rng().gen_range(4..12);
        let (min_x, max_x) = (self.size / window, self.size - (self.size / window));
        let (min_y, max_y) = (min_x, max_x);

        for _ in 0..num_live {
            let x: i32 = rand::thread_rng()
                .gen_range(min_x..max_x)
                .try_into()
                .expect("generate seed x i32 to u32");
            let y: i32 = rand::thread_rng()
                .gen_range(min_y..max_y)
                .try_into()
                .expect("generate seed y i32 to u32");

            let point = Point::new(x, y);
            let init_neighbors = {
                if init_neighbors > 4 {
                    4
                } else {
                    init_neighbors
                }
            };
            let neighbours = point.get_neighbors(init_neighbors);

            if self.is_printable(&point) && !self.live_points.contains_key(&point) {
                self.live_points.insert(point, true);
            }
            for neighbor in neighbours {
                if self.is_printable(&neighbor) && !self.live_points.contains_key(&neighbor) {
                    self.live_points.insert(neighbor, true);
                }
            }
        }
    }

    pub fn next(&mut self) {
        let mut new_live_points: HashMap<Point, bool> = HashMap::new();
        for (p, live) in &self.live_points {
            let population: i32 = p
                .get_neighbors(8)
                .iter()
                .filter_map(|p| {
                    if let Some(&true) = self.live_points.get(p) {
                        Some(1)
                    } else {
                        None
                    }
                })
                .sum();

            if *live && (population == 2 || population == 3) {
                new_live_points.insert(p.clone(), true);
                for neighbor in &p.get_neighbors(8) {
                    // Only add new neighbors if within printable size
                    if self.is_printable(&neighbor) && !new_live_points.contains_key(neighbor) {
                        new_live_points.insert(neighbor.clone(), false);
                    }
                }
            }

            if !live && population == 3 {
                new_live_points.insert(p.clone(), true);
                for neighbor in &p.get_neighbors(8) {
                    // Only add new neighbors if within printable size
                    if self.is_printable(&neighbor) && !new_live_points.contains_key(neighbor) {
                        new_live_points.insert(neighbor.clone(), false);
                    }
                }
            }
        }
        self.live_points = new_live_points
    }

    fn is_printable(&self, point: &Point) -> bool {
        point.x < self.size && point.x >= 0 && point.y < self.size && point.y >= 0
    }

    pub fn num_live(&self) -> i32 {
        self.live_points
            .iter()
            .filter_map(|(_, l)| if *l { Some(1) } else { None })
            .sum::<i32>()
    }

    pub fn print(&self) {
        for y in 0..self.size {
            let mut lines: Vec<String> = Vec::with_capacity(self.size as usize);
            for x in 0..self.size {
                let x = x.try_into().expect("x from u32 to i32");
                let y = y.try_into().expect("y from u32 to i32");
                let point = Point::new(x, y);
                let point_str = {
                    if let Some(true) = self.live_points.get(&point) {
                        "#"
                    } else {
                        "."
                    }
                };
                lines.push(point_str.to_string());
            }
            let line = lines.join(" ");
            println!("{line}");
        }
    }
}
